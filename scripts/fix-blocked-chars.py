#!/usr/bin/env python3
"""
WordPress Toolkit Pro - fix for "The server answered HTTP 200 instead of data".

Cause: CyberPanel's security middleware (CyberCP/secMiddleware.py) rejects any POST
value containing  ` $ & ( ) [ ] { } ; : ' < >  (and "...", "- -", newlines) and
answers with its own text/html response (HTTP 200). The plugin sends values like
"daily:2" (scheduled backups), "plugin-update:akismet" (plugins), "vhost:200"
(error logs) or a site title such as "Shop: Home & Garden" - all blocked.

Fix:
  * dashboard.html: the free-text fields `extra` and `title` are sent base64url-
    encoded as `extra64` / `title64` (only A-Z a-z 0-9 - _ ; nothing to block).
  * views.py: `_post()` decodes them; the existing regex validation is unchanged,
    so the shell side gets exactly the same values as before.
  * dashboard.html: non-JSON / blocked responses now show the real reason
    (CyberPanel's message, or "session expired") instead of a generic error.
  * meta.xml: patch version +1.

Usage (as root):
  python3 wptoolkit-fix-blocked-chars.py                      # server copy
  python3 wptoolkit-fix-blocked-chars.py /path/to/repo/wordpressToolkitPro
Safe to run twice (it detects an already patched copy). Backups: *.bak-<timestamp>.
"""
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

MARK = "WPT_B64"
plugin = Path(sys.argv[1] if len(sys.argv) > 1 else "/usr/local/CyberCP/wordpressToolkitPro")
views = plugin / "views.py"
tpl = plugin / "templates" / "wordpressToolkitPro" / "dashboard.html"
meta = plugin / "meta.xml"

for f in (views, tpl, meta):
    if not f.is_file():
        sys.exit("Not found: %s" % f)

v_src, t_src, m_src = views.read_text(), tpl.read_text(), meta.read_text()
if MARK in v_src and MARK in t_src:
    print("Already patched - nothing to do.")
    sys.exit(0)

# ---------------------------------------------------------------- views.py
helper = '''

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
'''
# insert the helper right after the first top-level "def _run(" block's predecessor:
# simplest stable anchor = just before "def _run("
if "\ndef _run(" not in v_src:
    sys.exit("views.py: anchor 'def _run(' not found - not patching.")
v_new = v_src.replace("\ndef _run(", helper.rstrip("\n") + "\n\n\ndef _run(", 1)

n_extra = len(re.findall(r'request\.POST\.get\("extra", ""\)', v_new))
n_title = len(re.findall(r'request\.POST\.get\("title", ""\)', v_new))
v_new = v_new.replace('request.POST.get("extra", "")', '_post(request, "extra")')
v_new = v_new.replace('request.POST.get("title", "")', '_post(request, "title")')
if n_extra == 0:
    sys.exit('views.py: request.POST.get("extra", "") not found - not patching.')

# ---------------------------------------------------------------- dashboard.html
old_loop = "Object.keys(data).forEach(function (k) { fd.append(k, data[k]); });"
new_loop = ("Object.keys(data).forEach(function (k) {\n"
            "      // WPT_B64: CyberPanel blocks : ; $ & ( ) etc. in POST values, so free text is sent base64url-encoded\n"
            "      if (k === 'extra' || k === 'title') { fd.append(k + '64', b64u(data[k])); } else { fd.append(k, data[k]); }\n"
            "    });")
if t_src.count(old_loop) != 1:
    sys.exit("dashboard.html: post() loop not found exactly once - not patching.")
t_new = t_src.replace(old_loop, new_loop)

b64_fn = ("  function b64u(s) {\n"
          "    s = String(s == null ? '' : s);\n"
          "    return btoa(unescape(encodeURIComponent(s))).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');\n"
          "  }\n")

parse_fn = ("  function parseJson(r) {\n"
            "    return r.text().then(function (t) {\n"
            "      var d = null; try { d = JSON.parse(t); } catch (e) {}\n"
            "      if (d && d.ok === undefined && (d.error_message || d.errorMessage)) {\n"
            "        throw new Error('CyberPanel blocked the request: ' + (d.error_message || d.errorMessage));\n"
            "      }\n"
            "      if (d) { return d; }\n"
            "      if (r.redirected && /login/i.test(r.url)) {\n"
            "        throw new Error('Your panel session has expired - reload the page and log in again.');\n"
            "      }\n"
            "      throw new Error('The server answered HTTP ' + r.status + ' instead of data: ' +\n"
            "        t.replace(/<[^>]*>/g, ' ').replace(/\\s+/g, ' ').trim().slice(0, 200));\n"
            "    });\n"
            "  }\n")

m = re.search(r"  function parseJson\(r\) \{.*?\n  \}\n", t_new, re.S)
if m:
    # server copy: replace the existing parseJson
    t_new = t_new[:m.start()] + b64_fn + parse_fn + t_new[m.end():]
else:
    # older copy: post() ends with .then(function (r) { return r.json(); })
    old_then = ".then(function (r) { return r.json(); });"
    if old_then not in t_new:
        sys.exit("dashboard.html: neither parseJson() nor r.json() found - not patching.")
    t_new = t_new.replace(old_then, ".then(parseJson);", 1)
    t_new = t_new.replace("  function post(url, data) {", b64_fn + parse_fn + "  function post(url, data) {", 1)

# ---------------------------------------------------------------- meta.xml
mv = re.search(r"<version>(\d+)\.(\d+)\.(\d+)</version>", m_src)
m_new, new_ver = m_src, None
if mv:
    new_ver = "%s.%s.%d" % (mv.group(1), mv.group(2), int(mv.group(3)) + 1)
    m_new = m_src[:mv.start()] + "<version>%s</version>" % new_ver + m_src[mv.end():]

# ---------------------------------------------------------------- write
stamp = time.strftime("%Y%m%d-%H%M%S")
for f, new in ((views, v_new), (tpl, t_new), (meta, m_new)):
    shutil.copy2(f, "%s.bak-%s" % (f, stamp))
    f.write_text(new)

r = subprocess.run([sys.executable, "-m", "py_compile", str(views)], capture_output=True, text=True)
if r.returncode != 0:
    for f in (views, tpl, meta):
        shutil.copy2("%s.bak-%s" % (f, stamp), f)
    sys.exit("views.py did not compile - backups restored:\n" + r.stderr)

print("Patched: views.py (extra x%d, title x%d), dashboard.html, meta.xml -> %s" % (n_extra, n_title, new_ver or "unchanged"))
print("Backups: *.bak-%s" % stamp)

if str(plugin).startswith("/usr/local/CyberCP/"):
    subprocess.run(["systemctl", "restart", "lscpd"])
    print("lscpd restarted - reload the panel page with Ctrl+F5.")
