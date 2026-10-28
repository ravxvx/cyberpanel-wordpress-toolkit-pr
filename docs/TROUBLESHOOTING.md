# Troubleshooting

| Problem | Cause / fix |
|---|---|
| Whole panel shows **HTTP 500** after installing | See the end of `/usr/local/CyberCP/logs/error.log`. A broken plugin registration can be removed with `pluginInstaller.py remove --pluginName wordpressToolkitPro`; if the panel is still down: `sed -i '/wordpressToolkitPro/d' /usr/local/CyberCP/CyberCP/settings.py /usr/local/CyberCP/CyberCP/urls.py`, remove the plugin's block from `baseTemplate/templates/baseTemplate/index.html`, then `systemctl restart lscpd`. |
| Menu link is missing | `sh /usr/local/CyberCP/wordpressToolkitPro/repair-menu.sh && systemctl restart lscpd`. The page is always available at `/wordpressToolkitPro/`. |
| Install log does not list `wptool.sh` | You installed an older zip. Remove and install the current release. |
| `can't open file '.../pluginInstaller/pluginInstaller.py'` | Run `cd /usr/local/CyberCP` first. |
| `unzip: cannot find ... wordpressToolkitPro.zip` | The zip must be named exactly `wordpressToolkitPro.zip` and be in `/usr/local/CyberCP`. |
| "Unknown domain" | The site must exist in CyberPanel (*Websites → Create Website*). |
| "public_html is not empty" when installing | Move or delete the existing files, or use the list/actions for an existing WordPress. |
| "no certificate / self-signed" on **Switch to https** | Issue SSL in CyberPanel first and wait until it succeeds. |
| 403 Forbidden on a site | `chown <siteuser>:nogroup /home/<domain>/public_html && chmod 750 /home/<domain>/public_html` (the plugin does this itself after install/update/restore). |
| List shows `?` for update counts | WP-CLI could not reach wordpress.org or the site has a PHP error; run `wp --allow-root --path=/home/<domain>/public_html core check-update` manually. |
| "another operation is already running" | A job for that site is still running; wait, or check `/var/log/wptoolkit/`. |
| An operation seems stuck | Read the newest file in `/var/log/wptoolkit/` (`job-<action>-<domain>.log`). |
| Sites on PHP 8.4/8.5 show plugin errors | Switch the site to PHP 8.3 in CyberPanel (*Manage → Change PHP*). |

Useful commands:

```bash
tail -n 50 /usr/local/CyberCP/logs/error.log      # panel errors
ls -lt /var/log/wptoolkit | head                  # recent plugin jobs
ls -lh /home/wptoolkit-backups/*/                 # backups
```
