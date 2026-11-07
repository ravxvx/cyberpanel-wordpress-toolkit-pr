#!/bin/bash
# WordPress Toolkit Pro - management actions, runs as root (started by the panel).
# Usage: wptool.sh ACTION DOMAIN|- EXTRA|- NONCE
#   ACTION: list | login | update | backup | backups | delbackup | restore | ssl | language | uninstall | errlog | debug | getsched | setsched | cron | plugins | pluginop | maint | verify | admins | resetpw | tidy
set -uo pipefail
ACTION="${1:-}"; DOMAIN="${2:--}"; EXTRA="${3:--}"; NONCE="${4:-}"
[ "$DOMAIN" = "-" ] && DOMAIN=""
[ "$EXTRA" = "-" ] && EXTRA=""
LOGDIR=/var/log/wptoolkit; BACKUPROOT=/home/wptoolkit-backups
umask 077
mkdir -p "$LOGDIR"; chmod 700 "$LOGDIR"
[[ "$ACTION" =~ ^(list|login|update|backup|backups|delbackup|restore|ssl|language|uninstall|errlog|debug|getsched|setsched|cron|plugins|pluginop|maint|verify|admins|resetpw|tidy)$ ]] || exit 1
[[ "$NONCE" =~ ^[0-9a-f]{12}$ ]] || exit 1

# one job of the same kind at a time (a duplicate start simply exits)
ID="$ACTION-${DOMAIN:-all}"
exec 9>"/var/run/wptoolkit-job-$ID.lock"
flock -n 9 || exit 0
exec >"$LOGDIR/job-$ID.log" 2>&1
echo "__START__ $NONCE"

fail(){ echo "ERROR: $*"; echo "__DONE__ FAIL"; exit 1; }
ok(){ echo "__DONE__ OK"; exit 0; }

PHPBIN=""
for v in lsphp83 lsphp84 lsphp82 lsphp81 lsphp85 lsphp80; do
  [ -x "/usr/local/lsws/$v/bin/php" ] && { PHPBIN="/usr/local/lsws/$v/bin/php"; break; }
done
[ -n "$PHPBIN" ] || fail "no lsphp binary found"
[ -x /usr/local/bin/wp ] || fail "WP-CLI not found (/usr/local/bin/wp)"
wpd(){ local d="$1"; shift; "$PHPBIN" -d memory_limit=512M /usr/local/bin/wp --allow-root --path="$d" "$@"; }

DBROOT="$(cat /etc/cyberpanel/mysqlPassword 2>/dev/null)"
MYSQLBIN="$(command -v mariadb || command -v mysql)"
DUMPBIN="$(command -v mariadb-dump || command -v mysqldump)"
export MYSQL_PWD="$DBROOT"

need_dir(){
  [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || fail "invalid domain"
  HOMEDIR="/home/$DOMAIN"; DIR="$HOMEDIR/public_html"
  [ -d "$DIR" ] || fail "$DIR does not exist - create the website in CyberPanel first"
  SITEUSER="$(stat -c %U "$HOMEDIR")"
  [ -n "$SITEUSER" ] && [ "$SITEUSER" != "root" ] || fail "cannot determine site owner"
  exec 8>"/var/run/wptoolkit-$DOMAIN.lock"
  flock -n 8 || fail "another operation is already running for $DOMAIN"
}
need_site(){
  need_dir
  [ -f "$DIR/wp-config.php" ] || fail "no WordPress found in $DIR"
}
fix_perms(){
  chown -R "$SITEUSER:$SITEUSER" "$DIR"
  chown "$SITEUSER:nogroup" "$DIR"
  chmod 750 "$DIR"
}
purge_cache(){ wpd "$DIR" litespeed-purge all --skip-themes >/dev/null 2>&1 || true; }

do_backup(){   # prints path of the new archive in BACKUP_FILE
  [ -n "$DBROOT" ] && [ -n "$DUMPBIN" ] || fail "database tools or root password not available"
  mkdir -p "$BACKUPROOT/$DOMAIN"; chmod 700 "$BACKUPROOT" "$BACKUPROOT/$DOMAIN"
  local ts dbname tmp
  ts="$(date +%Y%m%d-%H%M%S)"
  dbname="$(wpd "$DIR" config get DB_NAME --skip-plugins --skip-themes 2>/dev/null | tail -1)"
  [ -n "$dbname" ] || fail "cannot read DB_NAME from wp-config.php"
  tmp="$(mktemp -d "$BACKUPROOT/.tmp.XXXXXX")"
  "$DUMPBIN" -uroot --single-transaction --default-character-set=utf8mb4 "$dbname" > "$tmp/db.sql" \
    || { rm -rf "$tmp"; fail "database dump failed"; }
  BACKUP_FILE="$BACKUPROOT/$DOMAIN/$DOMAIN-$ts.tar.gz"
  tar -czf "$BACKUP_FILE" -C "$tmp" db.sql -C "$HOMEDIR" public_html \
    || { rm -rf "$tmp" "$BACKUP_FILE"; fail "archive failed"; }
  rm -rf "$tmp"
  tar -tzf "$BACKUP_FILE" >/dev/null 2>&1 || fail "archive verification failed"
  echo "Backup saved: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
  local keep
  keep="$(awk -F'|' -v d="$DOMAIN" '$1==d{print $3}' /etc/wptoolkit/schedule.conf 2>/dev/null | head -1)"
  [[ "$keep" =~ ^[0-9]+$ ]] && [ "$keep" -ge 2 ] || keep=7
  ls -1t "$BACKUPROOT/$DOMAIN"/*.tar.gz 2>/dev/null | tail -n +$((keep+1)) | xargs -r rm -f   # keep the newest N (default 7)
}

case "$ACTION" in

list)
  for cfg in /home/*/public_html/wp-config.php; do
    [ -e "$cfg" ] || continue
    dir="$(dirname "$cfg")"; dom="$(basename "$(dirname "$dir")")"
    [[ "$dom" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || continue
    ver="$(wpd "$dir" core version --skip-plugins --skip-themes 2>/dev/null | head -1)"
    core="$(wpd "$dir" core check-update --format=count --skip-plugins --skip-themes 2>/dev/null | tail -1)"
    plug="$(wpd "$dir" plugin list --update=available --format=count --skip-themes 2>/dev/null | tail -1)"
    thm="$(wpd "$dir" theme list --update=available --format=count --skip-plugins 2>/dev/null | tail -1)"
    url="$(wpd "$dir" option get siteurl --skip-plugins --skip-themes 2>/dev/null | head -1)"
    [[ "$core" =~ ^[0-9]+$ ]] || core="?"
    [[ "$plug" =~ ^[0-9]+$ ]] || plug="?"
    [[ "$thm" =~ ^[0-9]+$ ]] || thm="?"
    lang="$(wpd "$dir" option get WPLANG --skip-plugins --skip-themes 2>/dev/null | head -1)"
    [[ "$lang" =~ ^[a-z]{2,3}(_[A-Z]{2})?$ ]] || lang="en_US"
    echo "SITE|$dom|${ver:-?}|$core|$plug|$thm|${url//|/}|$lang"
  done
  ok ;;

login)
  need_site
  MU="$DIR/wp-content/mu-plugins"; mkdir -p "$MU"
  cat > "$MU/wpt-login.php" <<'PHP'
<?php
// WordPress Toolkit Pro: one-time admin login link (valid for 2 minutes, single use).
add_action('init', function () {
  if (empty($_GET['wpt_login']) || !is_string($_GET['wpt_login'])) { return; }
  $d = get_option('wpt_login_token');
  if (!$d) { return; }
  $p = explode('|', $d);
  if (count($p) !== 3) { return; }
  if (time() > (int)$p[1] || !hash_equals($p[0], hash('sha256', $_GET['wpt_login']))) {
    wp_die('Login link expired or invalid.');
  }
  delete_option('wpt_login_token');
  wp_set_current_user((int)$p[2]);
  wp_set_auth_cookie((int)$p[2], false);
  wp_safe_redirect(admin_url());
  exit;
});
PHP
  chmod 755 "$MU"; chmod 644 "$MU/wpt-login.php"
  chown -R "$SITEUSER:$SITEUSER" "$MU"
  uid="$(wpd "$DIR" user list --role=administrator --field=ID --number=1 --skip-plugins --skip-themes 2>/dev/null | head -1)"
  [[ "$uid" =~ ^[0-9]+$ ]] || fail "no administrator account found"
  tok="$(openssl rand -hex 24)"
  hash="$(printf '%s' "$tok" | sha256sum | cut -d' ' -f1)"
  exp=$(( $(date +%s) + 120 ))
  wpd "$DIR" option update wpt_login_token "$hash|$exp|$uid" --skip-plugins --skip-themes >/dev/null 2>&1 || fail "cannot store login token"
  url="$(wpd "$DIR" option get siteurl --skip-plugins --skip-themes 2>/dev/null | head -1)"
  [ -n "$url" ] || fail "cannot read site URL"
  echo "LOGINURL|$url/wp-login.php?wpt_login=$tok"
  echo "Link is valid for 2 minutes and works once."
  ok ;;

backup)
  need_site
  do_backup
  ok ;;

backups)
  [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || fail "invalid domain"
  for f in $(ls -1t "$BACKUPROOT/$DOMAIN"/*.tar.gz 2>/dev/null); do
    echo "BACKUP|$(basename "$f")|$(stat -c %s "$f")|$(stat -c %y "$f" | cut -c1-16)"
  done
  ok ;;

delbackup)
  [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || fail "invalid domain"
  [ -n "$EXTRA" ] || fail "no backup selected"
  n=0
  IFS=',' read -ra NAMES <<< "$EXTRA"
  for f in "${NAMES[@]}"; do
    [[ "$f" =~ ^[a-z0-9.-]+-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]] || fail "invalid backup name: $f"
    case "$f" in "$DOMAIN"-*) ;; *) fail "backup $f belongs to another site";; esac
    t="$BACKUPROOT/$DOMAIN/$f"
    if [ -f "$t" ] && [ ! -L "$t" ]; then rm -f -- "$t" && { n=$((n+1)); echo "Deleted $f"; }; else echo "Not found: $f"; fi
  done
  echo "Deleted $n backup(s)."
  ok ;;

errlog)
  [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || fail "invalid domain"
  [[ "$EXTRA" =~ ^(vhost|wp|php):(50|200|500)$ ]] || fail "invalid log request"
  HOMEDIR="/home/$DOMAIN"; [ -d "$HOMEDIR" ] || fail "$HOMEDIR does not exist"
  SRC="${EXTRA%%:*}"; NL="${EXTRA##*:}"
  case "$SRC" in
    vhost) LF="$HOMEDIR/logs/$DOMAIN.error_log"; LABEL="Web server error log (OpenLiteSpeed)";;
    wp)    LF="$HOMEDIR/public_html/wp-content/debug.log"; LABEL="WordPress debug.log";;
    php)   LF="$HOMEDIR/public_html/error_log"; LABEL="PHP error_log";;
  esac
  echo "== $LABEL =="
  if [ ! -e "$LF" ]; then
    echo "File not found: $LF"
    case "$SRC" in
      wp) echo "WordPress debug logging is off or nothing has been logged yet. Use \"Enable debug\" and reload the page that fails.";;
      php) echo "No PHP error_log in the site root - no PHP errors were written there.";;
      vhost) echo "Files in $HOMEDIR/logs:"; ls -1 "$HOMEDIR/logs" 2>/dev/null | head -20;;
    esac
    ok
  fi
  REAL="$(realpath "$LF" 2>/dev/null)"
  case "$REAL" in "$HOMEDIR"/*) ;; *) fail "log path leaves the site directory - refusing to read it";; esac
  [ -f "$REAL" ] || fail "not a regular file"
  echo "File: $LF   size: $(du -h "$REAL" | cut -f1)   modified: $(stat -c %y "$REAL" | cut -c1-16)"
  echo "--- last $NL lines ---"
  tail -n "$NL" "$REAL" | cut -c1-1500
  ok ;;

debug)
  need_site
  case "$EXTRA" in
    on)
      wpd "$DIR" config set WP_DEBUG true --raw --skip-plugins --skip-themes >/dev/null 2>&1 || fail "cannot edit wp-config.php"
      wpd "$DIR" config set WP_DEBUG_LOG true --raw --skip-plugins --skip-themes >/dev/null 2>&1
      wpd "$DIR" config set WP_DEBUG_DISPLAY false --raw --skip-plugins --skip-themes >/dev/null 2>&1
      WC="$DIR/wp-content"; HT="$WC/.htaccess"; touch "$HT"
      if ! grep -q "BEGIN WPT-DEBUGLOG" "$HT"; then
        printf '\n# BEGIN WPT-DEBUGLOG\n<Files "debug.log">\nOrder allow,deny\nDeny from all\n</Files>\n# END WPT-DEBUGLOG\n' >> "$HT"
      fi
      chown "$SITEUSER:$SITEUSER" "$DIR/wp-config.php" "$HT"; chmod 644 "$HT"
      purge_cache
      echo "Debug logging is ON (errors go to wp-content/debug.log, not shown on the page; the file is blocked from the web)."
      echo "Reload the failing page, then open \"WordPress debug.log\". Turn debug OFF when finished - it slows the site and the log grows."
      ;;
    off)
      wpd "$DIR" config set WP_DEBUG false --raw --skip-plugins --skip-themes >/dev/null 2>&1 || fail "cannot edit wp-config.php"
      wpd "$DIR" config set WP_DEBUG_LOG false --raw --skip-plugins --skip-themes >/dev/null 2>&1
      chown "$SITEUSER:$SITEUSER" "$DIR/wp-config.php"
      purge_cache
      echo "Debug logging is OFF."
      ;;
    clear)
      L="$DIR/wp-content/debug.log"
      if [ -f "$L" ] && [ ! -L "$L" ]; then : > "$L"; echo "debug.log cleared."; else echo "No debug.log to clear."; fi
      ;;
    *) fail "unknown debug option";;
  esac
  ok ;;

getsched)
  CONF=/etc/wptoolkit/schedule.conf
  for cfg in /home/*/public_html/wp-config.php; do
    [ -e "$cfg" ] || continue
    dom="$(basename "$(dirname "$(dirname "$cfg")")")"
    [[ "$dom" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || continue
    line="$(awk -F'|' -v d="$dom" '$1==d{print $2"|"$3}' "$CONF" 2>/dev/null | head -1)"
    freq="${line%%|*}"; keep="${line##*|}"
    [[ "$freq" =~ ^(off|daily|weekly)$ ]] || freq=off
    [[ "$keep" =~ ^[0-9]+$ ]] || keep=7
    last="$(ls -1t "$BACKUPROOT/$dom"/*.tar.gz 2>/dev/null | head -1)"; lastd=""
    [ -n "$last" ] && lastd="$(stat -c %y "$last" | cut -c1-16)"
    echo "SCHED|$dom|$freq|$keep|$lastd"
  done
  ok ;;

setsched)
  [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || fail "invalid domain"
  [[ "$EXTRA" =~ ^(off|daily|weekly):([2-9]|[1-5][0-9]|60)$ ]] || fail "invalid schedule"
  freq="${EXTRA%%:*}"; keep="${EXTRA##*:}"
  CONF=/etc/wptoolkit/schedule.conf
  mkdir -p /etc/wptoolkit; chmod 700 /etc/wptoolkit; touch "$CONF"; chmod 600 "$CONF"
  exec 7>/var/run/wptoolkit-sched.lock; flock 7
  awk -F'|' -v d="$DOMAIN" '$1!=d' "$CONF" > "$CONF.new"
  echo "$DOMAIN|$freq|$keep" >> "$CONF.new"; mv "$CONF.new" "$CONF"; chmod 600 "$CONF"
  SELF="$(readlink -f "$0")"
  if awk -F'|' '$2!="off"{f=1} END{exit !f}' "$CONF"; then
    printf '# WordPress Toolkit Pro scheduled backups\nSHELL=/bin/bash\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n15 3 * * * root /bin/bash %s cron - - 000000000000 >/dev/null 2>&1\n' "$SELF" > /etc/cron.d/wptoolkit
    chmod 644 /etc/cron.d/wptoolkit
    echo "Scheduled: $DOMAIN $freq, keeping the newest $keep backups. Backups run at 03:15 server time (weekly: Sunday)."
  else
    rm -f /etc/cron.d/wptoolkit
    echo "Scheduled backups are off for all sites. Keeping the newest $keep backups of $DOMAIN."
  fi
  ok ;;

cron)
  CONF=/etc/wptoolkit/schedule.conf
  SELF="$(readlink -f "$0")"
  dow="$(date +%u)"
  [ -f "$CONF" ] || { echo "No schedule configured."; ok; }
  while IFS='|' read -r dom freq keep; do
    [[ "$dom" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || continue
    case "$freq" in daily) ;; weekly) [ "$dow" = 7 ] || continue ;; *) continue ;; esac
    echo "== $dom ($freq) =="
    bash "$SELF" backup "$dom" - "$(openssl rand -hex 6)"
    tail -n 2 "$LOGDIR/job-backup-$dom.log" 2>/dev/null
  done < "$CONF"
  ok ;;

plugins)
  need_site
  wpd "$DIR" plugin list --fields=name,status,update,version --format=csv --skip-plugins --skip-themes 2>/dev/null | tail -n +2 | while IFS=',' read -r n st up ver; do
    [[ "$n" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] && echo "PLUGIN|$n|$st|$up|$ver"
  done
  wpd "$DIR" theme list --fields=name,status,update,version --format=csv --skip-plugins --skip-themes 2>/dev/null | tail -n +2 | while IFS=',' read -r n st up ver; do
    [[ "$n" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] && echo "THEME|$n|$st|$up|$ver"
  done
  ok ;;

pluginop)
  need_site
  [[ "$EXTRA" =~ ^(plugin-activate|plugin-deactivate|plugin-update|theme-activate|theme-update|plugins-deactivate-all|plugins-restore):([A-Za-z0-9][A-Za-z0-9._-]{0,99}|-)$ ]] || fail "invalid request"
  OP="${EXTRA%%:*}"; SLUG="${EXTRA#*:}"
  PREV="$BACKUPROOT/$DOMAIN/.prev-active"
  case "$OP" in
    plugin-activate)   wpd "$DIR" plugin activate "$SLUG" 2>&1 || fail "activation failed" ;;
    plugin-deactivate) wpd "$DIR" plugin deactivate "$SLUG" --skip-plugins --skip-themes 2>&1 || fail "deactivation failed" ;;
    plugin-update)     echo "== Safety backup =="; do_backup; wpd "$DIR" plugin update "$SLUG" 2>&1 || fail "update failed"; fix_perms; purge_cache ;;
    theme-activate)    wpd "$DIR" theme activate "$SLUG" 2>&1 || fail "activation failed" ;;
    theme-update)      echo "== Safety backup =="; do_backup; wpd "$DIR" theme update "$SLUG" 2>&1 || fail "update failed"; fix_perms; purge_cache ;;
    plugins-deactivate-all)
      mkdir -p "$BACKUPROOT/$DOMAIN"; chmod 700 "$BACKUPROOT" "$BACKUPROOT/$DOMAIN"
      wpd "$DIR" plugin list --status=active --field=name --skip-plugins --skip-themes 2>/dev/null > "$PREV"
      echo "Active plugins before: $(wc -l < "$PREV")"
      wpd "$DIR" plugin deactivate --all --skip-plugins --skip-themes 2>&1 || fail "deactivation failed"
      purge_cache
      echo "All plugins are off. Reload the site to see whether the problem is gone, then use \"Restore plugins\"." ;;
    plugins-restore)
      [ -s "$PREV" ] || fail "no saved plugin list for this site (nothing to restore)"
      while read -r pl; do
        [[ "$pl" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] && wpd "$DIR" plugin activate "$pl" 2>&1 | tail -1
      done < "$PREV"
      purge_cache; echo "Plugins restored." ;;
  esac
  ok ;;

maint)
  need_site
  [[ "$EXTRA" =~ ^(on|off|status)$ ]] || fail "invalid option"
  case "$EXTRA" in
    on)  wpd "$DIR" maintenance-mode activate --skip-plugins --skip-themes 2>&1 || fail "cannot activate maintenance mode"
         chown "$SITEUSER:$SITEUSER" "$DIR/.maintenance" 2>/dev/null; chmod 644 "$DIR/.maintenance" 2>/dev/null
         purge_cache
         echo "RESULT|ON"; echo "Maintenance mode is ON: visitors see a \"briefly unavailable\" page (HTTP 503, search engines treat it as temporary). Admins stay logged in." ;;
    off) wpd "$DIR" maintenance-mode deactivate --skip-plugins --skip-themes 2>&1 || true
         rm -f "$DIR/.maintenance"; purge_cache
         echo "RESULT|OFF"; echo "Maintenance mode is OFF." ;;
    status) if [ -f "$DIR/.maintenance" ]; then echo "RESULT|ON"; echo "Maintenance mode is ON."; else echo "RESULT|OFF"; echo "Maintenance mode is OFF."; fi ;;
  esac
  ok ;;

verify)
  need_site
  echo "== WordPress core files =="
  core_out="$(wpd "$DIR" core verify-checksums 2>&1)"; echo "$core_out" | head -60
  echo "== Plugins from wordpress.org =="
  plug_out="$(wpd "$DIR" plugin verify-checksums --all 2>&1)"; echo "$plug_out" | head -80
  bad="$(printf '%s\n%s\n' "$core_out" "$plug_out" | grep -v '^Error:' | grep -ciE "doesn't verify|should not exist|file was added|doesn't exist|is missing")"
  if [ "$bad" -gt 0 ]; then echo "RESULT|ISSUES|$bad"; echo "Found $bad file(s) that differ from the official release. Modified or unknown files can mean an infection or a manual edit - review them."
  else echo "RESULT|CLEAN"; echo "All checked files match the official releases (premium and custom plugins/themes cannot be checked this way)."; fi
  ok ;;

admins)
  need_site
  wpd "$DIR" user list --role=administrator --fields=ID,user_login,user_email --format=csv --skip-plugins --skip-themes 2>/dev/null | tail -n +2 | while IFS=',' read -r id lg em; do
    [[ "$id" =~ ^[0-9]+$ ]] && echo "ADMIN|$id|$lg|$em"
  done
  ok ;;

resetpw)
  need_site
  [[ "$EXTRA" =~ ^[0-9]{1,9}$ ]] || fail "invalid user id"
  wpd "$DIR" user list --role=administrator --field=ID --skip-plugins --skip-themes 2>/dev/null | grep -qx "$EXTRA" || fail "user $EXTRA is not an administrator of this site"
  pw="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 20)"
  [ "${#pw}" -ge 16 ] || fail "could not generate a password"
  wpd "$DIR" user update "$EXTRA" --user_pass="$pw" --skip-plugins --skip-themes >/dev/null 2>&1 || fail "password change failed"
  wpd "$DIR" user session destroy "$EXTRA" --all --skip-plugins --skip-themes >/dev/null 2>&1 || true
  echo "NEWPASS|$pw"
  echo "Password changed and the user was logged out everywhere."
  ok ;;

tidy)
  need_site
  [[ "$EXTRA" =~ ^(cache|db)$ ]] || fail "invalid option"
  if [ "$EXTRA" = cache ]; then
    wpd "$DIR" cache flush 2>&1 | tail -1
    purge_cache
    echo "Caches cleared (WordPress object cache and LiteSpeed Cache if installed)."
  else
    echo "== Safety backup =="; do_backup
    size_before="$(wpd "$DIR" db size --size_format=mb --skip-plugins --skip-themes 2>/dev/null | tail -1)"
    rev="$(wpd "$DIR" post list --post_type=revision --format=ids --skip-plugins --skip-themes 2>/dev/null)"
    echo "Revisions found: $(wc -w <<< "$rev")"
    [ -n "$rev" ] && printf '%s\n' $rev | xargs -r -n 100 "$PHPBIN" -d memory_limit=512M /usr/local/bin/wp --allow-root --path="$DIR" post delete --force --skip-plugins --skip-themes 2>&1 | tail -1
    for st in spam trash; do
      ids="$(wpd "$DIR" comment list --status=$st --format=ids --skip-plugins --skip-themes 2>/dev/null)"
      echo "Comments ($st): $(wc -w <<< "$ids")"
      [ -n "$ids" ] && printf '%s\n' $ids | xargs -r -n 100 "$PHPBIN" -d memory_limit=512M /usr/local/bin/wp --allow-root --path="$DIR" comment delete --force --skip-plugins --skip-themes 2>&1 | tail -1
    done
    echo "== Expired transients =="
    wpd "$DIR" transient delete --expired --skip-plugins --skip-themes 2>&1 | tail -1
    echo "== Optimizing tables =="
    wpd "$DIR" db optimize --skip-plugins --skip-themes 2>&1 | tail -1
    purge_cache
    echo "Database size: ${size_before:-?} MB -> $(wpd "$DIR" db size --size_format=mb --skip-plugins --skip-themes 2>/dev/null | tail -1) MB"
  fi
  ok ;;

update)
  need_site
  echo "== Safety backup =="
  do_backup
  echo "== Core =="
  wpd "$DIR" core update 2>&1
  wpd "$DIR" core update-db 2>&1 | tail -2
  echo "== Plugins =="
  wpd "$DIR" plugin update --all 2>&1
  echo "== Themes =="
  wpd "$DIR" theme update --all 2>&1
  wpd "$DIR" language core update >/dev/null 2>&1
  fix_perms; purge_cache
  echo "WordPress now: $(wpd "$DIR" core version --skip-plugins --skip-themes 2>/dev/null)"
  ok ;;

ssl)
  need_site
  CRT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  [ -f "$CRT" ] || fail "no certificate - issue SSL in CyberPanel first (Websites > List Websites > Manage > Issue SSL)"
  ISS="$(openssl x509 -in "$CRT" -noout -issuer 2>/dev/null | sed 's/^issuer=//')"
  SUB="$(openssl x509 -in "$CRT" -noout -subject 2>/dev/null | sed 's/^subject=//')"
  [ -n "$ISS" ] && [ "$ISS" != "$SUB" ] || fail "the certificate is self-signed - issue a real SSL in CyberPanel first"
  cur="$(wpd "$DIR" option get siteurl --skip-plugins --skip-themes 2>/dev/null | head -1)"
  echo "Current site URL: $cur"
  echo "== Safety backup =="
  do_backup
  echo "== Switching addresses to https =="
  wpd "$DIR" search-replace "http://$DOMAIN" "https://$DOMAIN" --all-tables --skip-columns=guid 2>&1 | tail -3
  wpd "$DIR" search-replace "http://www.$DOMAIN" "https://www.$DOMAIN" --all-tables --skip-columns=guid 2>&1 | tail -3
  HT="$DIR/.htaccess"; touch "$HT"
  if ! grep -q "BEGIN WPT-HTTPS" "$HT"; then
    { printf '# BEGIN WPT-HTTPS\nRewriteEngine On\nRewriteCond %%{HTTPS} !=on\nRewriteRule ^(.*)$ https://%%{HTTP_HOST}/$1 [R=301,L]\n# END WPT-HTTPS\n\n'; cat "$HT"; } > "$HT.new" && mv "$HT.new" "$HT"
    echo "Added http->https redirect to .htaccess"
  fi
  chmod 644 "$HT"
  fix_perms; purge_cache
  echo "Site URL now: $(wpd "$DIR" option get siteurl --skip-plugins --skip-themes 2>/dev/null | head -1)"
  ok ;;

restore)
  need_dir
  [[ "$EXTRA" =~ ^[a-z0-9.-]+-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]] || fail "invalid backup name"
  case "$EXTRA" in "$DOMAIN"-*) ;; *) fail "backup belongs to another site";; esac
  SRC="$BACKUPROOT/$DOMAIN/$EXTRA"
  [ -f "$SRC" ] || fail "backup not found"
  [ -n "$DBROOT" ] && [ -n "$MYSQLBIN" ] || fail "database tools or root password not available"
  STG="$(mktemp -d "$BACKUPROOT/.restore.XXXXXX")"
  trap 'rm -rf "$STG"' EXIT
  echo "== Unpacking $EXTRA =="
  tar -xzf "$SRC" -C "$STG" || fail "cannot unpack backup"
  [ -f "$STG/db.sql" ] && [ -f "$STG/public_html/wp-config.php" ] || fail "backup is incomplete"
  DBN="$(wpd "$STG/public_html" config get DB_NAME --skip-plugins --skip-themes 2>/dev/null | tail -1)"
  [[ "$DBN" =~ ^[A-Za-z0-9_]+$ ]] || fail "cannot read DB_NAME from the backup"
  if [ -f "$DIR/wp-config.php" ]; then
    echo "== Safety backup of the current state =="
    do_backup
  else
    echo "No WordPress currently installed here - skipping the safety backup."
  fi
  DBU="$(wpd "$STG/public_html" config get DB_USER --skip-plugins --skip-themes 2>/dev/null | tail -1)"
  DBPW="$(wpd "$STG/public_html" config get DB_PASSWORD --skip-plugins --skip-themes 2>/dev/null | tail -1)"
  echo "== Restoring database $DBN =="
  printf '%s\n' "DROP DATABASE IF EXISTS \`$DBN\`; CREATE DATABASE \`$DBN\` CHARACTER SET utf8mb4;" | "$MYSQLBIN" -uroot || fail "cannot recreate database"
  if [[ "$DBU" =~ ^[A-Za-z0-9_]{1,32}$ ]] && [[ "$DBPW" =~ ^[A-Za-z0-9_@#%^*+=.:,-]{6,128}$ ]]; then
    # recreate the database user (it is gone after "Remove WP") with the password from the backup's wp-config.php
    printf '%s\n' "CREATE USER IF NOT EXISTS '$DBU'@'localhost' IDENTIFIED BY '$DBPW'; ALTER USER '$DBU'@'localhost' IDENTIFIED BY '$DBPW'; GRANT ALL ON \`$DBN\`.* TO '$DBU'@'localhost'; FLUSH PRIVILEGES;" | "$MYSQLBIN" -uroot \
      || fail "cannot recreate the database user"
  else
    echo "WARNING: database user/password in the backup could not be recreated automatically."
  fi
  "$MYSQLBIN" -uroot "$DBN" < "$STG/db.sql" || fail "database import failed (files untouched; safety backup kept)"
  echo "== Restoring files =="
  find "$DIR" -mindepth 1 -delete
  cp -a "$STG/public_html/." "$DIR/" || fail "copying files failed"
  fix_perms; purge_cache
  echo "Restore finished."
  ok ;;

language)
  need_site
  [[ "$EXTRA" =~ ^[a-z]{2,3}(_[A-Z]{2})?$ ]] || fail "invalid language code"
  if [ "$EXTRA" != "en_US" ]; then
    echo "== Downloading language packs ($EXTRA) =="
    wpd "$DIR" language core install "$EXTRA" 2>&1 || fail "cannot install the core language pack for $EXTRA"
    wpd "$DIR" language plugin install --all "$EXTRA" 2>&1 | tail -3
    wpd "$DIR" language theme install --all "$EXTRA" 2>&1 | tail -3
  fi
  echo "== Switching site language =="
  if ! wpd "$DIR" site switch-language "$EXTRA" 2>&1; then
    if [ "$EXTRA" = "en_US" ]; then wpd "$DIR" option update WPLANG "" 2>&1; else wpd "$DIR" option update WPLANG "$EXTRA" 2>&1; fi
  fi
  echo "== Resetting per-user language to the site default =="
  for uid in $(wpd "$DIR" user list --field=ID --skip-plugins --skip-themes 2>/dev/null); do
    [[ "$uid" =~ ^[0-9]+$ ]] && wpd "$DIR" user meta delete "$uid" locale --skip-plugins --skip-themes >/dev/null 2>&1
  done
  fix_perms; purge_cache
  echo "Site language is now: $EXTRA"
  ok ;;

uninstall)
  need_site
  [ "$EXTRA" = "$DOMAIN" ] || fail "confirmation text does not match the domain"
  [ -n "$DBROOT" ] && [ -n "$MYSQLBIN" ] || fail "database tools or root password not available"
  DBN="$(wpd "$DIR" config get DB_NAME --skip-plugins --skip-themes 2>/dev/null | tail -1)"
  DBU="$(wpd "$DIR" config get DB_USER --skip-plugins --skip-themes 2>/dev/null | tail -1)"
  [[ "$DBN" =~ ^[A-Za-z0-9_]+$ ]] && [[ "$DBU" =~ ^[A-Za-z0-9_]+$ ]] || fail "cannot read database name/user from wp-config.php"
  case "$DBN" in mysql|information_schema|performance_schema|sys|cyberpanel|postfix|roundcube|rainloop|docker) fail "refusing to drop system database $DBN";; esac
  case "$DBU" in root|mysql|cyberpanel|mariadb.sys) fail "refusing to drop system user $DBU";; esac
  echo "== Safety backup (kept after removal) =="
  do_backup
  echo "== Removing database $DBN and user $DBU =="
  printf '%s\n' "DROP DATABASE IF EXISTS \`$DBN\`; DROP USER IF EXISTS '$DBU'@'localhost'; FLUSH PRIVILEGES;" | "$MYSQLBIN" -uroot || fail "cannot drop database"
  echo "== Removing files from $DIR =="
  find "$DIR" -mindepth 1 -maxdepth 1 ! -name '.well-known' ! -name 'cgi-bin' -exec rm -rf {} +
  fix_perms
  echo "WordPress removed from $DOMAIN (the website itself stays in CyberPanel; public_html is empty)."
  echo "The last backup is in $BACKUPROOT/$DOMAIN/ - you can restore it from "Restore from backup"."
  ok ;;
esac
