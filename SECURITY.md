# Security

## What the plugin can do

It runs shell scripts **as root** on your server, on behalf of CyberPanel administrators: it reads site files and databases, writes backups, drops databases (only when you type the domain to confirm) and creates one-time WordPress login links. Install it only on servers where every CyberPanel administrator is trusted with root-level control of the hosted sites.

## Safeguards

* Every endpoint requires a logged-in CyberPanel **administrator** and a CSRF token.
* Domains are checked against CyberPanel's website table and a strict regular expression; backup names, locales and actions are allow-listed; all arguments are shell-quoted.
* Destructive actions need a confirmation (typed domain for removal, dialog for restore/update/https) and take a backup first. The removal script refuses to drop system databases/users.
* Login links are single-use and expire after 2 minutes. Logs live in a root-only directory (`/var/log/wptoolkit`, mode 700).
* The generated admin password is shown once in the browser and saved in `/root/wp-<domain>.txt` (mode 600). Change it after first login.

## Things to know

* The one-time login link on an **http** site travels unencrypted; switch to https first.
* The plugin's job logs can contain the one-time link and installer passwords. They are root-only; delete old files in `/var/log/wptoolkit/` if you wish.
* Backups contain the complete site and database (including `wp-config.php` secrets). They are stored root-only in `/home/wptoolkit-backups/`; protect any off-server copy.

## Reporting a vulnerability

Please do **not** open a public issue. Use GitHub's **"Report a vulnerability"** (Security tab → Advisories) on this repository, or contact the maintainer privately. Include the version, steps to reproduce and impact.
