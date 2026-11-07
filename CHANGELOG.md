# Changelog

## 3.7.0
Includes 3.5.0 and 3.6.0.
* **Delete backups** (one or several, with confirmation); filename is validated and only files of that site can be removed.
* **Scheduled backups**: per-site off / daily / weekly (Sunday) at 03:15 via `/etc/cron.d/wptoolkit`, and a configurable number of backups to keep (2-60, applies to safety backups too; default 7).
* **Plugins and themes** manager: activate, deactivate, update one item (safety backup first), "Deactivate all plugins" and "Restore plugins" for white-screen debugging.
* **Error logs**: web server error log, WordPress `debug.log`, PHP `error_log`; enable/disable WordPress debug logging (log is not displayed and is blocked in `.htaccess`) and clear it. Log paths that leave the site directory (symlinks) are refused.
* **Maintenance mode** on/off/status (HTTP 503).
* **File integrity check** (`core verify-checksums` and `plugin verify-checksums`).
* **Administrators list and password reset** (random 20-character password, shown once, sessions destroyed).
* **Clear cache** and **Clean database** (revisions, spam/trash comments, expired transients, optimize; safety backup first).

## 3.4.1
* Robustness: the sidebar link is now written in a safe form (`{% url ... as var %}` + `{% if %}`), so if the plugin's URL ever disappears (e.g. a CyberPanel upgrade resets `urls.py`) the link is just hidden instead of breaking every panel page with HTTP 500. `repair-menu.sh` upgrades an older link automatically.
* Robustness: CyberPanel internals are imported lazily, so a future CyberPanel refactor can only break the plugin's own pages, never the whole panel.
* Security: the MariaDB root password and the new database user's password no longer appear on any command line (`MYSQL_PWD` environment variable + SQL via stdin).

## 3.4.0
* Restore works for sites whose WordPress was removed ("Restore from backup" card); DB user is recreated from the backup.

## 3.3.0
* Full English interface.

## 3.2.0
* New: change WordPress language, remove WordPress (with backup and typed confirmation).

## 3.1.0
* Redesigned dashboard: stat tiles, badges, readable in light and dark panel themes.

## 3.0.0
* New: site list, one-click login, update, backup/restore, switch to https.

## 2.2.0
* Plugin adds its own sidebar link and restarts the panel; `repair-menu.sh`.

## 2.0.0
* Rewrite of the original 1.0.3 plugin: fixed HTTP 500 (`NoReverseMatch` caused by a namespaced URL), fixed "no access to public_html" (privileged scripts via `ProcessUtilities`), DB creation with the CyberPanel MariaDB root password, correct file ownership, rollback on failure.
