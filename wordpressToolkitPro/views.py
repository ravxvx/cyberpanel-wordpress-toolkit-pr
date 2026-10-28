import os
import re
import secrets
import shlex

from django.http import JsonResponse
from django.views.decorators.http import require_POST

from plogical.acl import ACLManager
from plogical.httpProc import httpProc
from plogical.processUtilities import ProcessUtilities

PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(PLUGIN_DIR, "wpinstall.sh")
JOB_SCRIPT = os.path.join(PLUGIN_DIR, "wptool.sh")
LOG_DIR = "/var/log/wptoolkit"
DOMAIN_RE = re.compile(r"^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$")
LOGIN_RE = re.compile(r"^[A-Za-z0-9_.-]{3,40}$")
MAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")
LOCALE_RE = re.compile(r"^[a-z]{2,3}(_[A-Z]{2})?$")
NONCE_RE = re.compile(r"^[0-9a-f]{12}$")
FILE_RE = re.compile(r"^[a-z0-9.-]+-[0-9]{8}-[0-9]{6}\.tar\.gz$")
ACTIONS = ("list", "login", "update", "backup", "backups", "restore", "ssl", "language", "uninstall")


def _is_admin(request):
    try:
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
        domains, meta = [], {}
    proc = httpProc(request, "wordpressToolkitPro/dashboard.html", {"domains": domains, "meta": meta}, "admin")
    return proc.render()


@require_POST
def deploy(request):
    if not _is_admin(request):
        return _deny()

    domain = request.POST.get("domain", "").strip().lower()
    login = request.POST.get("login", "").strip()
    mail = request.POST.get("email", "").strip()
    title = request.POST.get("title", "").strip()[:80]
    scheme = request.POST.get("scheme", "auto")
    locale = request.POST.get("locale", "en_US")
    lscache = "1" if request.POST.get("litespeed") == "1" else "0"

    if domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Unknown domain - create the website in CyberPanel first."})
    if not LOGIN_RE.match(login):
        return JsonResponse({"ok": False, "error": "Admin login: 3-40 characters (letters, digits, _ . -)."})
    if not MAIL_RE.match(mail):
        return JsonResponse({"ok": False, "error": "Invalid e-mail address."})
    if scheme not in ("auto", "http", "https") or not LOCALE_RE.match(locale):
        return JsonResponse({"ok": False, "error": "Invalid options."})

    args = " ".join(shlex.quote(a) for a in (SCRIPT, domain, login, mail, title, lscache, scheme, locale))
    log = "%s/%s.log" % (LOG_DIR, domain)
    inner = "mkdir -p %s && chmod 700 %s && : > %s && chmod 600 %s && setsid nohup bash %s > %s 2>&1 < /dev/null &" % (
        LOG_DIR, LOG_DIR, shlex.quote(log), shlex.quote(log), args, shlex.quote(log))
    ProcessUtilities.outputExecutioner("bash -c " + shlex.quote(inner))
    return JsonResponse({"ok": True, "message": "Installation started."})


@require_POST
def status(request):
    if not _is_admin(request):
        return _deny()
    domain = request.POST.get("domain", "").strip().lower()
    if domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Unknown domain."})
    out = ProcessUtilities.outputExecutioner("cat %s" % shlex.quote("%s/%s.log" % (LOG_DIR, domain)))
    out = out if isinstance(out, str) else ""
    done = "__DONE__" in out
    success = "__DONE__ OK" in out
    text = out.replace("__DONE__ OK", "").replace("__DONE__ FAIL", "")
    return JsonResponse({"ok": True, "log": text, "done": done, "success": success})


def _job_log(action, domain):
    return "%s/job-%s-%s.log" % (LOG_DIR, action, domain or "all")


@require_POST
def job(request):
    if not _is_admin(request):
        return _deny()
    action = request.POST.get("action", "")
    domain = request.POST.get("domain", "").strip().lower()
    extra = request.POST.get("extra", "").strip()
    if action not in ACTIONS:
        return JsonResponse({"ok": False, "error": "Unknown action."})
    if action == "list":
        domain = ""
    elif domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Unknown domain."})
    if action == "restore":
        if not FILE_RE.match(extra) or not extra.startswith(domain + "-"):
            return JsonResponse({"ok": False, "error": "Invalid backup name."})
    elif action == "language":
        if not LOCALE_RE.match(extra):
            return JsonResponse({"ok": False, "error": "Invalid language code."})
    elif action == "uninstall":
        if extra != domain:
            return JsonResponse({"ok": False, "error": "Type the domain name exactly to confirm."})
    else:
        extra = ""
    nonce = secrets.token_hex(6)
    args = " ".join(shlex.quote(a) for a in (JOB_SCRIPT, action, domain or "-", extra or "-", nonce))
    inner = "mkdir -p %s && chmod 700 %s && setsid nohup bash %s > /dev/null 2>&1 < /dev/null &" % (LOG_DIR, LOG_DIR, args)
    ProcessUtilities.outputExecutioner("bash -c " + shlex.quote(inner))
    return JsonResponse({"ok": True, "nonce": nonce})


@require_POST
def jobstatus(request):
    if not _is_admin(request):
        return _deny()
    action = request.POST.get("action", "")
    domain = request.POST.get("domain", "").strip().lower()
    nonce = request.POST.get("nonce", "")
    if action not in ACTIONS or not NONCE_RE.match(nonce):
        return JsonResponse({"ok": False, "error": "Bad request."})
    if action == "list":
        domain = ""
    elif domain not in _domains() or not DOMAIN_RE.match(domain):
        return JsonResponse({"ok": False, "error": "Unknown domain."})
    out = ProcessUtilities.outputExecutioner("cat %s" % shlex.quote(_job_log(action, domain)))
    out = out if isinstance(out, str) else ""
    marker = "__START__ " + nonce
    if marker not in out:
        return JsonResponse({"ok": True, "started": False, "done": False, "success": False, "log": ""})
    text = out.split(marker, 1)[1]
    done = "__DONE__" in text
    success = "__DONE__ OK" in text
    text = text.replace("__DONE__ OK", "").replace("__DONE__ FAIL", "").strip("\n")
    return JsonResponse({"ok": True, "started": True, "done": done, "success": success, "log": text})
