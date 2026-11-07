# Using the plugin

Open **WP Toolkit Pro** in the CyberPanel sidebar. The list loads automatically; **Refresh list** scans again. One operation runs at a time; while it runs the buttons are disabled and the **Operation log** shows live output.

## Site list

For each WordPress found in `/home/<domain>/public_html`: WordPress version and language, PHP version and SSL flag (from CyberPanel), and counts of available updates (Core / Plugins / Themes). The three tiles show totals.

## Log in

**Log in** creates a single-use link valid for 2 minutes and shows a green **Open wp-admin** button. It logs in as the first administrator. The link goes to `/wp-login.php?wpt_login=...` (this URL is never cached).

## Update

**Update** takes a safety backup, then updates core, database, plugins, themes and language packs and purges the LiteSpeed cache. If the backup fails, nothing is updated.

## Backup and Backups (restore)

* **Backup** creates `/home/wptoolkit-backups/<domain>/<domain>-YYYYMMDD-HHMMSS.tar.gz` containing `db.sql` and `public_html/`. By default the 7 newest are kept (change it in **Scheduled backups**).
* **Backups** lists them; **Restore** replaces the site's files and database after a confirmation. If WordPress is currently installed, a safety backup of the current state is taken first.
* **Restore from backup** (card below the table) lets you pick any CyberPanel website, including one whose WordPress was removed. The database user is recreated from the credentials stored in the backup's `wp-config.php`.

* **Delete** (per row) or tick several backups and click **Delete selected**. Deleted backups cannot be recovered.

## Scheduled backups

For every site choose **Off / Daily / Weekly (Sunday)** and how many of the newest backups to keep (2-60), then **Save**. Backups run at 03:15 server time from `/etc/cron.d/wptoolkit`. The number to keep applies to all backups of the site, including the safety backups taken before updates, SSL switch and restore. The table shows the date of the last backup.

## Plugins and themes

Pick a site and **Load** (or use **Plugins** in the site row). Each plugin or theme can be activated, deactivated or updated (a safety backup is taken before an update). **Deactivate all plugins** saves the list of active plugins and turns them all off so you can find a faulty plugin; **Restore plugins** activates the saved list again.

## Error logs

Choose the site, the log (web server error log, WordPress `debug.log` or PHP `error_log`) and the number of lines. **Enable debug** turns on `WP_DEBUG` and `WP_DEBUG_LOG` (errors are written to `wp-content/debug.log`, never displayed, and the file is blocked from the web in `wp-content/.htaccess`); **Disable debug** turns it off; **Clear debug.log** empties the file. Turn debug off when you are done.

## Maintenance, security and cleanup

* **Maintenance ON / OFF / Status**: WordPress maintenance mode (visitors get HTTP 503).
* **Check file integrity**: runs `wp core verify-checksums` and `wp plugin verify-checksums --all`. Modified or unknown files are reported; premium and custom plugins cannot be checked.
* **List administrators / Reset password**: sets a random 20-character password, ends all sessions of that user and shows the password once. The one-time value also stays in the root-only operation log until the next job of that kind.
* **Clear cache**: WordPress object cache and LiteSpeed Cache.
* **Clean database**: after a safety backup deletes post revisions, spam and trashed comments and expired transients, then optimizes the tables.

## Switch to https

1. Issue an SSL certificate in CyberPanel (*Websites → List Websites → Manage → Issue SSL*) and make sure the domain's DNS points to the server.
2. Click **Switch to https**. After a safety backup the plugin runs `search-replace` for `http://domain` and `http://www.domain`, adds an http→https redirect block (`# BEGIN WPT-HTTPS`) to `.htaccess` and purges the cache.

It refuses to run with a self-signed certificate.

## Language

**Language** downloads the translations for core, plugins and themes and switches the site language (English US/UK, Irish, Polish, German, French, Spanish). Per-user language settings are reset to the site default.

## Remove WP

Type the domain name to confirm. The plugin takes a backup, drops the WordPress database and its DB user, and deletes everything in `public_html` except `.well-known` and `cgi-bin`. The website itself stays in CyberPanel; you can install WordPress again or restore the backup.

## Install a new WordPress

Requirements: the website already exists in CyberPanel and `public_html` is empty (only the default `index.html`, `.well-known`, `cgi-bin`, `.htaccess` are allowed).

1. Open **Install a new WordPress**, choose the website, title, admin login (avoid `admin`) and e-mail, language and URL scheme.
2. Click **Install WordPress**. The log shows each step.
3. At the end you get the site URL, login and a generated password. **Copy it immediately**; it is also saved in `/root/wp-<domain>.txt` (mode 600).

URL scheme **Auto** uses https only when a real (non-self-signed) certificate already exists, otherwise http; switch later with **Switch to https**.

The installer creates a random database (`wp_<name>_<hex>`), user and password, downloads WordPress with WP-CLI, sets permalinks to `/%postname%/`, removes Hello Dolly and Akismet, optionally installs LiteSpeed Cache, and sets file ownership for CyberPanel (`public_html` owned by the site user, group `nogroup`, mode 750). On failure it drops the database and removes the downloaded files.

## Where things are stored

| What | Where |
|---|---|
| Backups | `/home/wptoolkit-backups/<domain>/` |
| Operation logs (contain the one-time login link / passwords, root-only) | `/var/log/wptoolkit/` |
| Installer credentials | `/root/wp-<domain>.txt` |
