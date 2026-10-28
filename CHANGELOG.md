# Changelog

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
