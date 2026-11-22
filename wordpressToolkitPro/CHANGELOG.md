# Changelog

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
