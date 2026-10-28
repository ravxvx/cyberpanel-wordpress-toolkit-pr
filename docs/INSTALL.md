# Installation, update and removal

All commands are run **on the server as root** (SSH) unless stated otherwise.

## 1. Install

### Option A: download on the server (recommended)

```bash
cd /usr/local/CyberCP
curl -fL -o wordpressToolkitPro.zip \
  https://github.com/ravxvx/cyberpanel-wordpress-toolkit-pro/releases/latest/download/wordpressToolkitPro.zip
PYTHONPATH=/usr/local/CyberCP /usr/local/CyberCP/bin/python \
  pluginInstaller/pluginInstaller.py install --pluginName wordpressToolkitPro
rm -f /usr/local/CyberCP/wordpressToolkitPro.zip
```

### Option B: upload from your computer

1. Download `wordpressToolkitPro.zip` from the [Releases](../../releases) page.
2. Upload it (Windows PowerShell / macOS / Linux terminal on **your computer**, adjust the path and IP):
   ```
   scp "C:\path\to\wordpressToolkitPro.zip" root@SERVER_IP:/root/wpt.zip
   ```
3. On the server:
   ```bash
   cp /root/wpt.zip /usr/local/CyberCP/wordpressToolkitPro.zip
   cd /usr/local/CyberCP
   PYTHONPATH=/usr/local/CyberCP /usr/local/CyberCP/bin/python \
     pluginInstaller/pluginInstaller.py install --pluginName wordpressToolkitPro
   rm -f /usr/local/CyberCP/wordpressToolkitPro.zip /root/wpt.zip
   ```

> The installer unzips `wordpressToolkitPro.zip` from the current directory into `/usr/local/CyberCP`, so the file name must be exactly `wordpressToolkitPro.zip` and you must `cd /usr/local/CyberCP` first.

### What the installer does

It unzips the plugin, registers it in `CyberCP/settings.py` and `CyberCP/urls.py`, adds the sidebar link ("WP Toolkit Pro", placed above "WordPress"), creates `/var/log/wptoolkit/` and restarts the panel (`lscpd`) a few seconds later.

### Check

* The install log should list `wptool.sh` among the extracted files and end with "Plugin successfully installed".
* `grep version /usr/local/CyberCP/wordpressToolkitPro/meta.xml` shows the installed version.
* Refresh the panel (Ctrl+F5) and open **WP Toolkit Pro** (or go to `https://SERVER_IP:8090/wordpressToolkitPro/`).

## 2. Update

The plugin has no migrations or data of its own, so updating is "remove, then install the new zip". Your sites and backups are not touched.

```bash
cd /usr/local/CyberCP
PYTHONPATH=/usr/local/CyberCP /usr/local/CyberCP/bin/python \
  pluginInstaller/pluginInstaller.py remove --pluginName wordpressToolkitPro
# put the new wordpressToolkitPro.zip here (see step 1), then:
PYTHONPATH=/usr/local/CyberCP /usr/local/CyberCP/bin/python \
  pluginInstaller/pluginInstaller.py install --pluginName wordpressToolkitPro
rm -f /usr/local/CyberCP/wordpressToolkitPro.zip
```

## 3. Remove

```bash
cd /usr/local/CyberCP
PYTHONPATH=/usr/local/CyberCP /usr/local/CyberCP/bin/python \
  pluginInstaller/pluginInstaller.py remove --pluginName wordpressToolkitPro
```

This removes the plugin, its registration and the sidebar link. It does **not** delete:

| Left in place | Path |
|---|---|
| Backups | `/home/wptoolkit-backups/` |
| Operation logs | `/var/log/wptoolkit/` |
| Credentials saved by the installer | `/root/wp-DOMAIN.txt` |
| One-time-login helper inside each WordPress | `wp-content/mu-plugins/wpt-login.php` (harmless without a token; delete it if you like) |

## 4. If the menu link is missing

Some CyberPanel versions do not contain the marker the installer uses, and upgrades overwrite the template. Re-add the link (this also replaces an older link with the safe form):

```bash
sh /usr/local/CyberCP/wordpressToolkitPro/repair-menu.sh
systemctl restart lscpd
```

## 5. Before you install: recommended safety net

Take a snapshot of the server at your hosting provider (e.g. the Contabo control panel) before installing or updating any panel plugin.
