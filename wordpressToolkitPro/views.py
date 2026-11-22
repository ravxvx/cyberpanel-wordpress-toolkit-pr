import os
import re
import secrets
import shlex
import shutil
import subprocess
import platform
from datetime import datetime, timezone
import uuid
import functools
import traceback

from django.http import JsonResponse, HttpResponse
from django.views.decorators.http import require_POST


PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(PLUGIN_DIR, "bin", "wpinstall.sh")
JOB_SCRIPT = os.path.join(PLUGIN_DIR, "bin", "wptool.sh")
LOG_DIR = "/var/log/wptoolkit"
DOMAIN_RE = re.compile(r"^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$")
LOGIN_RE = re.compile(r"^[A-Za-z0-9_.-]{3,40}$")
MAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")
LOCALE_RE = re.compile(r"^[a-z]{2,3}(_[A-Z]{2})?$")
NONCE_RE = re.compile(r"^[0-9a-f]{12}$")
MIGRATION_ID_RE = re.compile(r"^[0-9a-f]{32}$")
FILE_RE = re.compile(r"^[a-z0-9.-]+-[0-9]{8}-[0-9]{6}\.tar\.gz$")
ACTIONS = ("list", "login", "update", "backup", "backups", "delbackup", "restore", "ssl", "language", "uninstall", "errlog", "debug", "getsched", "setsched", "plugins", "pluginop", "maint", "verify", "admins", "resetpw", "tidy", "migrate", "speed", "speedinfo", "serverop", "selfupdate")
SCHED_RE = re.compile(r"^(off|daily|weekly):([2-9]|[1-5][0-9]|60)$")
PLUGOP_RE = re.compile(r"^(plugin-activate|plugin-deactivate|plugin-update|theme-activate|theme-update|plugins-deactivate-all|plugins-restore):([A-Za-z0-9][A-Za-z0-9._-]{0,99}|-)$")
MAINT_RE = re.compile(r"^(on|off|status)$")
TIDY_RE = re.compile(r"^(cache|db)$")
UID_RE = re.compile(r"^[0-9]{1,9}$")
LOGREQ_RE = re.compile(r"^(vhost|wp|php):(50|200|500)$")
SPEED_RE = re.compile(r"^(status|test|redis-on|redis-off|opt-safe|opt-full|opt-off|php-(74|80|81|82|83|84|85))$")
SERVEROP_RE = re.compile(r"^(redis-install|autocache-on|autocache-off|phpredis-(74|80|81|82|83|84|85))$")
SERVER_ACTIONS = ("list", "getsched", "speedinfo", "serverop", "selfupdate")
LOCAL_RE = re.compile(r"^local:[A-Za-z0-9._-]{1,120}\.(zip|tar|tar\.gz|tgz)$")
MIG_ROOT = "/home/wptoolkit-migrations"
MIG_INCOMING = MIG_ROOT + "/incoming"
ERRLOG = "/var/log/wptoolkit/plugin-errors.log"


def _log_error(where):
    """Write the traceback to a root-only log so a 500 can always be diagnosed."""
    try:
        os.makedirs(os.path.dirname(ERRLOG), mode=0o700, exist_ok=True)
        fd = os.open(ERRLOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a") as handle:
            handle.write("[%s] %s\n%s\n" % (datetime.now(timezone.utc).isoformat(), where, traceback.format_exc()))
    except Exception:
        pass


def guarded(view):
    """Turn any unexpected exception into a readable JSON error instead of an HTTP 500 page."""
    @functools.wraps(view)
    def wrapper(request, *args, **kwargs):
        try:
            return view(request, *args, **kwargs)
        except Exception as exc:
            _log_error(view.__name__)
            return JsonResponse({"ok": False, "error": "Internal error in %s: %s: %s (details: %s)" % (
                view.__name__, type(exc).__name__, str(exc)[:200], ERRLOG)})
    return wrapper



def _post(request, key, default=""):
    # WPT_B64: free-text fields arrive base64url-encoded (<key>64) because CyberPanel's
    # secMiddleware rejects values containing : ; $ & ( ) [ ] { } < > ' before any view runs.
    raw = request.POST.get(key + "64")
    if raw is None:
        return request.POST.get(key, default)
    try:
        import base64
        return base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode("utf-8")
    except Exception:
        return default


def _run(command):
    # Imported lazily: if CyberPanel moves this module, only the plugin pages break - not every panel page.
    from plogical.processUtilities import ProcessUtilities
    return ProcessUtilities.outputExecutioner(command)


def _is_admin(request):
    try:
        from plogical.acl import ACLManager
        user_id = request.session["userID"]
        return bool(ACLManager.loadedACL(user_id)["admin"])
    except Exception:
        return False


def _deny():
    return JsonResponse({"ok": False, "error": "Administrator login required."}, status=403)


def _domains():
    from websiteFunctions.models import Websites
    return sorted(Websites.objects.values_list("domain", flat=True))


def _meta():
    from websiteFunctions.models import Websites
    return {w.domain: {"php": w.phpSelection, "ssl": int(w.ssl)} for w in Websites.objects.all()}


def dashboard(request):
    try:
        domains = _domains()
        meta = _meta()
    except Exception:
        _log_error("dashboard-data")
        domains, meta = [], {}
    try:
        from plogical.httpProc import httpProc
        proc = httpProc(request, "wordpressToolkitPro/dashboard.html", {"domains": domains, "meta": meta}, "admin")
        return proc.render()
    except Exception as exc:
        _log_error("dashboard-render")
        return HttpResponse("<h3>WordPress Toolkit Pro could not render its page</h3><p>%s: %s</p>"
                            "<p>Details: <code>%s</code>. Fix: <code>sh /usr/local/CyberCP/wordpressToolkitPro/bin/repair-menu.sh "
                            "&amp;&amp; systemctl restart lscpd</code></p>" % (type(exc).__name__, str(exc)[:300].replace("<", "&lt;"), ERRLOG), status=500)


@require_POST
@guarded
def deploy(request):
    if not _is_admin(request):
        return _deny()

    domain = request.POST.get("domain", "").strip().lower()
    login = request.POST.get("login", "").strip()
    mail = request.POST.get("email", "").strip()
    title = _post(request, "title").strip()[:80]
    scheme = request.POST.get("scheme", "auto")
    locale = request.POST.get("locale", "en_US")
    lscache = "1" if request.POST.get("litespeed") == "1" else "0"
    redis = "1" if request.POST.get("redis") == "1" and lscache == "1" else "0"

    if domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Unknown domain - create the website in CyberPanel first."})
    if not LOGIN_RE.match(login):
        return JsonResponse({"ok": False, "error": "Admin login: 3-40 characters (letters, digits, _ . -)."})
    if not MAIL_RE.match(mail):
        return JsonResponse({"ok": False, "error": "Invalid e-mail address."})
    if scheme not in ("auto", "http", "https") or not LOCALE_RE.match(locale):
        return JsonResponse({"ok": False, "error": "Invalid options."})

    args = " ".join(shlex.quote(a) for a in (SCRIPT, domain, login, mail, title, lscache, scheme, locale, redis))
    log = "%s/%s.log" % (LOG_DIR, domain)
    inner = "mkdir -p %s && chmod 700 %s && : > %s && chmod 600 %s && setsid nohup bash %s > %s 2>&1 < /dev/null &" % (
        LOG_DIR, LOG_DIR, shlex.quote(log), shlex.quote(log), args, shlex.quote(log))
    _run("bash -c " + shlex.quote(inner))
    return JsonResponse({"ok": True, "message": "Installation started."})


@require_POST
@guarded
def status(request):
    if not _is_admin(request):
        return _deny()
    domain = request.POST.get("domain", "").strip().lower()
    if domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Unknown domain."})
    out = _run("cat %s" % shlex.quote("%s/%s.log" % (LOG_DIR, domain)))
    out = out if isinstance(out, str) else ""
    done = "__DONE__" in out
    success = "__DONE__ OK" in out
    text = out.replace("__DONE__ OK", "").replace("__DONE__ FAIL", "")
    return JsonResponse({"ok": True, "log": text, "done": done, "success": success})


def _job_log(action, domain):
    return "%s/job-%s-%s.log" % (LOG_DIR, action, domain or "all")


@require_POST
@guarded
def job(request):
    if not _is_admin(request):
        return _deny()
    action = request.POST.get("action", "")
    domain = request.POST.get("domain", "").strip().lower()
    extra = _post(request, "extra").strip()
    if action not in ACTIONS:
        return JsonResponse({"ok": False, "error": "Unknown action."})
    if action in SERVER_ACTIONS:
        domain = ""
    elif domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Unknown domain."})
    if action == "restore":
        if not FILE_RE.match(extra) or not extra.startswith(domain + "-"):
            return JsonResponse({"ok": False, "error": "Invalid backup name."})
    elif action == "delbackup":
        names = [n for n in extra.split(",") if n]
        if not names or len(names) > 50 or not all(FILE_RE.match(n) and n.startswith(domain + "-") for n in names):
            return JsonResponse({"ok": False, "error": "Invalid backup selection."})
        extra = ",".join(names)
    elif action == "errlog":
        if not LOGREQ_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid log request."})
    elif action == "setsched":
        if not SCHED_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid schedule."})
    elif action == "pluginop":
        if not PLUGOP_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid request."})
    elif action == "maint":
        if not MAINT_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid option."})
    elif action == "tidy":
        if not TIDY_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid option."})
    elif action == "resetpw":
        if not UID_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid user."})
    elif action == "debug":
        if extra not in ("on", "off", "clear"):
            return JsonResponse({"ok": False, "error": "Invalid option."})
    elif action == "language":
        if not LOCALE_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid language code."})
    elif action == "migrate":
        if not LOCAL_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Choose an archive from the server folder."})
    elif action == "uninstall":
        if extra != domain:
            return JsonResponse({"ok": False, "error": "Type the domain name exactly to confirm."})
    elif action == "speed":
        if not SPEED_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid option."})
    elif action == "serverop":
        if not SERVEROP_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid option."})
    elif action == "selfupdate":
        if extra not in ("check", "apply"):
            return JsonResponse({"ok": False, "error": "Invalid option."})
    else:
        extra = ""
    nonce = secrets.token_hex(6)
    args = " ".join(shlex.quote(a) for a in (JOB_SCRIPT, action, domain or "-", extra or "-", nonce))
    inner = "mkdir -p %s && chmod 700 %s && setsid nohup bash %s > /dev/null 2>&1 < /dev/null &" % (LOG_DIR, LOG_DIR, args)
    _run("bash -c " + shlex.quote(inner))
    return JsonResponse({"ok": True, "nonce": nonce})


@require_POST
@guarded
def jobstatus(request):
    if not _is_admin(request):
        return _deny()
    action = request.POST.get("action", "")
    domain = request.POST.get("domain", "").strip().lower()
    nonce = request.POST.get("nonce", "")
    if action not in ACTIONS or not NONCE_RE.match(nonce):
        return JsonResponse({"ok": False, "error": "Bad request."})
    if action in SERVER_ACTIONS:
        domain = ""
    elif domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Unknown domain."})
    out = _run("cat %s" % shlex.quote(_job_log(action, domain)))
    out = out if isinstance(out, str) else ""
    marker = "__START__ " + nonce
    if marker not in out:
        return JsonResponse({"ok": True, "started": False, "done": False, "success": False, "log": ""})
    text = out.split(marker, 1)[1]
    done = "__DONE__" in text
    success = "__DONE__ OK" in text
    text = text.replace("__DONE__ OK", "").replace("__DONE__ FAIL", "").strip("\n")
    return JsonResponse({"ok": True, "started": True, "done": done, "success": success, "log": text})


# Read-only diagnostics and allowlisted log viewer. Both endpoints are admin-only.
DIAG_LOG_DIR = "/var/log/wptoolkit"
CYBERPANEL_LOG = "/usr/local/lscp/logs/error.log"
LOG_NAME_RE = re.compile(r"^(?:[a-z0-9.-]+\.log|job-[a-z0-9.-]+-[a-z0-9.-]+\.log)$")


def _safe_tail(path, lines=150, max_bytes=262144):
    try:
        if not os.path.isfile(path) or os.path.islink(path):
            return ""
        size = os.path.getsize(path)
        with open(path, "rb") as handle:
            if size > max_bytes:
                handle.seek(-max_bytes, os.SEEK_END)
            text = handle.read(max_bytes).decode("utf-8", "replace")
        text = "\n".join(text.splitlines()[-lines:])
        text = re.sub(r"(?i)(password|passwd|dbpass|secret|token|api[_-]?key)(\s*[=:]\s*)\S+", r"\1\2[REDACTED]", text)
        text = re.sub(r"(?i)(authorization:\s*bearer\s+)\S+", r"\1[REDACTED]", text)
        return text
    except (OSError, PermissionError):
        return ""


def _version(command):
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=5, check=False)
        output = (result.stdout or "").strip().splitlines()
        return output[0][:160] if output else "Unavailable"
    except Exception:
        return "Unavailable"


@require_POST
@guarded
def diagnostics(request):
    if not _is_admin(request):
        return _deny()
    checks = []

    def add(name, status, detail):
        checks.append({"name": name, "status": status, "detail": str(detail)[:240]})

    add("Python", "ok", platform.python_version())
    try:
        import django
        add("Django", "ok", django.get_version())
    except Exception as exc:
        add("Django", "error", type(exc).__name__ + ": " + str(exc))
    try:
        from django.conf import settings
        installed = "wordpressToolkitPro" in getattr(settings, "INSTALLED_APPS", [])
        add("Plugin registration", "ok" if installed else "warning",
            "Registered in INSTALLED_APPS" if installed else "Not found in INSTALLED_APPS")
        try:
            from django.urls import reverse
            reverse("wordpressToolkitPro")
            add("Dashboard URL", "ok", "Named route resolves")
        except Exception as exc:
            add("Dashboard URL", "error", type(exc).__name__ + ": " + str(exc))
    except Exception as exc:
        add("Django settings", "error", type(exc).__name__ + ": " + str(exc))

    php = _version(["php", "-v"])
    maria = _version(["mariadb", "--version"])
    add("PHP CLI", "ok" if php != "Unavailable" else "warning", php)
    add("MariaDB client", "ok" if maria != "Unavailable" else "warning", maria)
    add("CyberPanel error log", "ok" if os.path.isfile(CYBERPANEL_LOG) else "warning",
        "Present" if os.path.isfile(CYBERPANEL_LOG) else "Not present")
    add("Toolkit log directory", "ok" if os.path.isdir(DIAG_LOG_DIR) else "warning",
        "Present" if os.path.isdir(DIAG_LOG_DIR) else "Not present")
    try:
        usage = shutil.disk_usage("/home")
        add("Free disk space (/home)", "ok" if usage.free > 1024 ** 3 else "warning",
            "%.2f GB free" % (usage.free / (1024 ** 3)))
    except Exception as exc:
        add("Free disk space (/home)", "warning", str(exc))
    for label, path in (("WP-CLI", "/usr/local/bin/wp"), ("Toolkit job script", os.path.join(PLUGIN_DIR, "bin", "wptool.sh")),
                        ("Installer script", os.path.join(PLUGIN_DIR, "bin", "wpinstall.sh"))):
        add(label, "ok" if os.access(path, os.X_OK) or (label == "WP-CLI" and os.path.isfile(path)) else "error",
            "Found" if os.path.isfile(path) else "Missing: " + path)
    lsphp = [d for d in ("lsphp85", "lsphp84", "lsphp83", "lsphp82", "lsphp81", "lsphp80") if os.path.isfile("/usr/local/lsws/%s/bin/php" % d)]
    add("LiteSpeed PHP (lsphp)", "ok" if lsphp else "error", ", ".join(lsphp) or "No lsphp binary found")
    add("Migration folder", "ok" if os.path.isdir(MIG_INCOMING) else "warning", MIG_INCOMING if os.path.isdir(MIG_INCOMING) else "Created on first use")
    add("Plugin error log", "ok" if not os.path.isfile(ERRLOG) else "warning",
        "No errors recorded" if not os.path.isfile(ERRLOG) else "Errors recorded - open plugin-errors.log below")
    add("Plugin directory", "ok" if os.path.isdir(PLUGIN_DIR) else "error", PLUGIN_DIR)
    extractor = os.path.join(PLUGIN_DIR, "bin", "migrate_extract.py")
    add("Migration extractor", "ok" if os.path.isfile(extractor) else "error",
        "Present" if os.path.isfile(extractor) else "Missing")

    errors = sum(1 for item in checks if item["status"] == "error")
    warnings = sum(1 for item in checks if item["status"] == "warning")
    return JsonResponse({"ok": True, "checked_at": datetime.now(timezone.utc).isoformat(),
                         "summary": {"total": len(checks), "errors": errors, "warnings": warnings},
                         "checks": checks})


@require_POST
@guarded
def toolkit_logs(request):
    if not _is_admin(request):
        return _deny()
    source = request.POST.get("source", "toolkit")
    name = request.POST.get("name", "")
    if source == "list":
        names = []
        try:
            for n in sorted(os.listdir(DIAG_LOG_DIR), key=lambda x: -os.path.getmtime(os.path.join(DIAG_LOG_DIR, x))):
                if LOG_NAME_RE.match(n) and os.path.isfile(os.path.join(DIAG_LOG_DIR, n)):
                    names.append(n)
        except OSError:
            pass
        return JsonResponse({"ok": True, "files": names[:60]})
    lines = request.POST.get("lines", "150")
    if lines not in ("50", "150", "300"):
        return JsonResponse({"ok": False, "error": "Invalid line count."}, status=400)
    if source == "cyberpanel" and name == "error.log":
        path = CYBERPANEL_LOG
    elif source == "toolkit" and LOG_NAME_RE.match(name) and "/" not in name and ".." not in name:
        path = os.path.join(DIAG_LOG_DIR, name)
    else:
        return JsonResponse({"ok": False, "error": "Log is not allowlisted."}, status=400)
    if not os.path.isfile(path):
        return JsonResponse({"ok": True, "log": "", "message": "Log file does not exist yet."})
    if not os.access(path, os.R_OK):
        return JsonResponse({"ok": False, "error": "CyberPanel cannot read this log file."}, status=403)
    return JsonResponse({"ok": True, "log": _safe_tail(path, int(lines)),
                         "message": "Newest lines shown; common credential patterns are redacted."})


@require_POST
@guarded
def migrate_upload(request):
    """Accept a single-site WordPress archive and start an isolated migration job."""
    if not _is_admin(request):
        return _deny()
    domain = request.POST.get("domain", "").strip().lower()
    uploaded = request.FILES.get("backup")
    if domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Create the destination website in CyberPanel first."}, status=400)
    if not uploaded:
        return JsonResponse({"ok": False, "error": "Choose a backup archive first."}, status=400)
    name = uploaded.name.lower()
    if not (name.endswith(".zip") or name.endswith(".tar") or name.endswith(".tar.gz") or name.endswith(".tgz")):
        return JsonResponse({"ok": False, "error": "Supported formats: ZIP, TAR, TAR.GZ and TGZ."}, status=400)
    max_size = 2 * 1024 * 1024 * 1024
    if uploaded.size > max_size:
        return JsonResponse({"ok": False, "error": "Backup exceeds the 2 GB upload limit."}, status=413)
    migration_id = uuid.uuid4().hex
    nonce = secrets.token_hex(6)
    root = MIG_ROOT
    try:
        os.makedirs(root, mode=0o700, exist_ok=True)
        os.chmod(root, 0o700)
        # Keep at least 1 GiB free after receiving the upload; extraction performs
        # its own strict expanded-size checks before any destination changes.
        free_bytes = shutil.disk_usage(root).free
        if free_bytes < uploaded.size + (1024 * 1024 * 1024):
            return JsonResponse({"ok": False, "error": "Not enough free disk space for a safe upload. Free at least the archive size plus 1 GB."}, status=507)
        path = os.path.join(root, migration_id + (".zip" if name.endswith(".zip") else ".tar.gz"))
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(fd, "wb") as target:
                for chunk in uploaded.chunks():
                    target.write(chunk)
                target.flush()
                os.fsync(target.fileno())
        except Exception:
            try: os.unlink(path)
            except OSError: pass
            raise
    except OSError as exc:
        return JsonResponse({"ok": False, "error": "Could not store the uploaded backup: %s" % exc}, status=507)
    args = " ".join(shlex.quote(a) for a in (JOB_SCRIPT, "migrate", domain, migration_id, nonce))
    inner = "mkdir -p %s && chmod 700 %s && setsid nohup bash %s > /dev/null 2>&1 < /dev/null &" % (shlex.quote(LOG_DIR), shlex.quote(LOG_DIR), args)
    _run("bash -c " + shlex.quote(inner))
    return JsonResponse({"ok": True, "nonce": nonce, "message": "Upload received. Migration validation has started."})


@require_POST
@guarded
def migrate_files(request):
    """List archives that were copied to the server folder (scp / SFTP) for migration."""
    if not _is_admin(request):
        return _deny()
    items = []
    try:
        os.makedirs(MIG_INCOMING, mode=0o700, exist_ok=True)
        for name in sorted(os.listdir(MIG_INCOMING)):
            path = os.path.join(MIG_INCOMING, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            if not LOCAL_RE.match("local:" + name):
                continue
            st = os.stat(path)
            items.append({"name": name, "size": st.st_size, "mtime": int(st.st_mtime)})
    except OSError as exc:
        return JsonResponse({"ok": False, "error": "Cannot read %s: %s" % (MIG_INCOMING, exc)})
    return JsonResponse({"ok": True, "folder": MIG_INCOMING, "files": items})
