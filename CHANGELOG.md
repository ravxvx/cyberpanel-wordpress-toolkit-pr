# Changelog

## 4.1.1
- **Safety for the Redis object cache:** after turning it on, the Toolkit loads the home page; if the site does not answer with 2xx/3xx, the object cache is switched off again at once (the `object-cache.php` drop-in is removed) and the last error lines are shown. This also applies to the nightly automatic cache.
- "Turn off" also removes the `object-cache.php` drop-in, so LiteSpeed Cache cannot bring a broken one back.

## 4.1.0
Built on the production 3.10.1 (migration, diagnostics, green design), which is now also the code on GitHub.

### New layout
- **Site first.** The *Sites* tab lists all sites; click one to open it with its own tabs: Overview, Plugins & themes, Backups, Speed, Security, Logs, Settings. The separate Plugins, Maintenance and Logs tabs with their own site pickers are gone.
- Top tabs: Sites, Backups (schedules and restore for any website), Migrate (unchanged), Server & speed (server status, Redis, PHP versions, automatic cache and the Toolkit diagnostics and logs), New WordPress.
- Activity is a sticky bar at the bottom that opens its log while something runs. Deep links such as `#site=example.com&tab=speed` open a site directly.

### Speed
- Per site: speed test (server response time from the page cache and without it), Redis object cache on/off via LiteSpeed Cache (installs it if missing; every site gets its own Redis database), PHP version switch with a health check and automatic rollback, LiteSpeed optimization presets Off / Safe / Full.
- Server: RAM, CPU and load with warnings, one-click Redis installation (256 MB, `allkeys-lru`, 64 databases), the redis extension for every installed lsphp, and an optional nightly job (04:40) that turns on the object cache on sites that have LiteSpeed Cache but not the object cache yet.
- Installer: option to turn on the Redis object cache right after installing.


## 4.0.0
* **New tabbed layout.** Top tabs: Sites, Backups, Server & speed, Install WordPress. Click a site to open it; each site has its own tabs (Overview, Plugins & themes, Backups, Speed, Security, Logs, Settings), so there are no more per-card site pickers. The operation log is a collapsible bar at the bottom. Links like `#site=example.com&tab=speed` open a site directly.
* **Speed tab per site:** speed test (server response time from cache and without cache), Redis object cache on/off through LiteSpeed Cache (installed automatically if missing; every site gets its own Redis database), PHP version switch with a health check and automatic rollback, LiteSpeed optimization presets Off / Safe (minify CSS, JS, HTML) / Full (+ deferred JavaScript).
* **Server & speed tab:** RAM, CPU and load with warnings, Redis status and one-click installation (256 MB limit, LRU, 64 databases), redis extension status and installation per installed PHP version, and an optional nightly job (04:40) that turns on the Redis object cache on sites that have LiteSpeed Cache but not the object cache yet.
* **Installer:** new option to turn on the Redis object cache right after installing.
* The site list shows the PHP version read from the site's virtual host.

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
