# Architecture

```
wordpressToolkitPro/
  meta.xml            plugin metadata read by CyberPanel's installer
  urls.py             routes (no app_name - see below)
  views.py            admin-only endpoints; start/poll background jobs
  templates/.../dashboard.html   the whole UI (HTML + CSS + JS, no external libraries)
  wpinstall.sh        fresh-install script (root)
  wptool.sh           list/login/update/backup/backups/restore/ssl/language/uninstall (root)
  repair-menu.sh      adds the sidebar link if missing
  pre_install / post_install / pre_remove   hooks run by CyberPanel's installer
```

## Request flow

1. The browser POSTs to `/wordpressToolkitPro/job/` (or `/deploy/` for the installer) with the CSRF token.
2. `views.py` checks that the session user is a CyberPanel **administrator**, validates every input against a strict allow-list / regular expression (domain must exist in CyberPanel's `Websites` table), then starts the script **as root through `ProcessUtilities`** (CyberPanel's own mechanism, which talks to `lscpd`) in the background with `nohup`/`setsid`. Arguments are quoted with `shlex.quote`.
3. The script writes a log to `/var/log/wptoolkit/job-<action>-<domain>.log` (root-only, 0600). The first line is `__START__ <nonce>`, the last `__DONE__ OK|FAIL`.
4. The browser polls `/wordpressToolkitPro/jobstatus/` every 1.5 s. The view reads the log (again as root), checks the nonce so that an old log is never mistaken for the new run, and returns the text.
5. Machine-readable lines (`SITE|...`, `BACKUP|...`, `LOGINURL|...`) in the log are rendered into tables and buttons by the JS (all with `textContent`, never `innerHTML` for log data).

## Design notes

* **No `app_name` in `urls.py`.** CyberPanel's installer injects `{% url 'wordpressToolkitPro' %}` into the sidebar, so the dashboard route must have exactly that global name. A namespaced `app_name` causes `NoReverseMatch` and breaks every panel page (HTTP 500).
* **Why root scripts?** The panel process cannot read `public_html` (mode 750, group `nogroup`). Running through `ProcessUtilities` is how CyberPanel itself performs privileged work.
* **Locking.** `flock` per job and per domain (`/var/run/wptoolkit-*.lock`) prevents overlapping operations.
* **Login links.** A tiny must-use plugin (`wp-content/mu-plugins/wpt-login.php`) accepts `?wpt_login=<token>` on `wp-login.php`, compares the SHA-256 of the token with a value stored via WP-CLI (`wpt_login_token = hash|expiry|userId`), deletes it on use, and logs the first administrator in.
* **Backups** use `mariadb-dump --single-transaction` plus `tar`, authenticated with the root password from `/etc/cyberpanel/mysqlPassword` (exported as `MYSQL_PWD`, not on the command line).

* **The sidebar link cannot break the panel.** It is inserted as one line: `{% url 'wordpressToolkitPro' as wpt_url %}{% if wpt_url %}<a ...>{% endif %}`. With `as`, Django does not raise `NoReverseMatch`; the link is hidden if the route is missing. `views.py` imports CyberPanel modules inside functions for the same reason (a failing import at URL-load time would take every panel page down).
* **After a CyberPanel upgrade** the registrations in `settings.py` / `urls.py` / `index.html` may be reset. Reinstall the plugin (remove, then install) or run `repair-menu.sh` (menu only).

## Building a release

```bash
sh scripts/build-zip.sh        # creates dist/wordpressToolkitPro.zip
```

The zip must contain the folder `wordpressToolkitPro/` at its root and must be named `wordpressToolkitPro.zip`. Build it on Linux/macOS/WSL or with the GitHub Actions workflow (executable bits are set by the installer's `post_install` anyway, but zips made with Windows `Compress-Archive` use backslashes and break `unzip` on Linux, so use `tar -a -c -f` on Windows).
