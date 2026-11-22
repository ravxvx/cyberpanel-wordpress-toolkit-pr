# Changelog

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


## 3.10.0
### Fixed
- **Migration always failed**: `wptool.sh` used an undefined `$PLUGIN_DIR` (the script runs with `set -u`). It is now resolved from the script location.
- **HTTP 500 pages**: every endpoint is wrapped; an unexpected error now returns a readable message and writes the traceback to `/var/log/wptoolkit/plugin-errors.log`. The dashboard shows a repair hint instead of a bare 500.
- The browser UI no longer fails with "Unexpected token <" when the server returns an HTML error; it explains where to look.
- Migration: stray `.sql` files inside the website folder no longer confuse dump detection; dumps are never left in the web root.
- Migration: `USE`/`CREATE DATABASE` lines and `DEFINER` clauses are stripped; MySQL 8 collation `utf8mb4_0900_ai_ci` is mapped for MariaDB.
- Migration: the old server's `object-cache.php` drop-in and Apache `.htaccess` are set aside (they commonly break OpenLiteSpeed) and a clean `.htaccess` is written.
- Migration moves files instead of copying (no double disk use) and verifies the database connection before switching.
- The "Migration log (all)" entry pointed to a file that never existed; the log list now shows real files.

### Added
- Migration from a **server folder** (`/home/wptoolkit-migrations/incoming/`) – no browser upload limit.
- Tabbed interface (Sites, Backups, Migrate, Plugins, Maintenance, Logs and diagnostics, New WordPress) and a new visual design.
- More diagnostics: WP-CLI, lsphp, scripts, migration folder, panel error log.

### Changed
- Repository layout: scripts moved to `plugin/bin/`, documentation to `docs/`; unused Django stubs (models, admin, tests, migrations, apps) removed.

## 3.9.0
System diagnostics and log viewer.

## 3.8.2
Safer migration (staging, rollback), extraction limits, Modern Light interface.
