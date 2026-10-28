#!/bin/bash
# WordPress Toolkit Pro - management actions, runs as root (started by the panel).
# Usage: wptool.sh ACTION DOMAIN|- EXTRA|- NONCE
#   ACTION: list | login | update | backup | backups | restore | ssl | language | uninstall
set -uo pipefail
ACTION="${1:-}"; DOMAIN="${2:--}"; EXTRA="${3:--}"; NONCE="${4:-}"
[ "$DOMAIN" = "-" ] && DOMAIN=""
[ "$EXTRA" = "-" ] && EXTRA=""
LOGDIR=/var/log/wptoolkit; BACKUPROOT=/home/wptoolkit-backups
umask 077
mkdir -p "$LOGDIR"; chmod 700 "$LOGDIR"
[[ "$ACTION" =~ ^(list|login|update|backup|backups|restore|ssl|language|uninstall)$ ]] || exit 1
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
  ls -1t "$BACKUPROOT/$DOMAIN"/*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f   # keep the 7 newest
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
