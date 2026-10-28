#!/bin/bash
# WordPress Toolkit Pro - installer, runs as root (started by the panel through lscpd).
# Usage: wpinstall.sh DOMAIN WPUSER WPMAIL TITLE LITESPEED(1|0) SCHEME(auto|http|https) LOCALE
set -uo pipefail
DOMAIN="${1:-}"; WPUSER="${2:-}"; WPMAIL="${3:-}"; TITLE="${4:-}"
LSCACHE="${5:-1}"; SCHEME="${6:-auto}"; LOCALE="${7:-en_US}"

done_fail(){ echo "ERROR: $*"; echo "__DONE__ FAIL"; exit 1; }

[[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])$ ]] || done_fail "invalid domain"
[[ "$WPUSER" =~ ^[A-Za-z0-9_.-]{3,40}$ ]] || done_fail "invalid admin login (3-40 chars: letters, digits, _ . -)"
[[ "$WPMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || done_fail "invalid e-mail"
[[ "$SCHEME" =~ ^(auto|http|https)$ ]] || done_fail "invalid scheme"
[[ "$LOCALE" =~ ^[a-z]{2,3}(_[A-Z]{2})?$ ]] || done_fail "invalid locale"
TITLE="$(printf '%s' "$TITLE" | tr -cd 'A-Za-z0-9 ._,&-' | cut -c1-80)"
[ -n "$TITLE" ] || TITLE="$DOMAIN"

exec 9>"/var/run/wptoolkit-$DOMAIN.lock"
flock -n 9 || done_fail "an installation for $DOMAIN is already running"

HOMEDIR="/home/$DOMAIN"; DIR="$HOMEDIR/public_html"
[ -d "$DIR" ] || done_fail "$DIR does not exist - create the website in CyberPanel first"
SITEUSER="$(stat -c %U "$HOMEDIR")"
[ -n "$SITEUSER" ] && [ "$SITEUSER" != "root" ] || done_fail "cannot determine the site owner of $HOMEDIR"
echo "Site: $DOMAIN  owner: $SITEUSER  dir: $DIR"

[ -e "$DIR/wp-config.php" ] && done_fail "WordPress is already installed in $DIR"
# anything except the CyberPanel default files blocks the install
EXTRA="$(ls -A "$DIR" | grep -vxE 'index\.html|\.well-known|cgi-bin|\.htaccess|\.litespeed_flag' || true)"
[ -z "$EXTRA" ] || done_fail "public_html is not empty: $(echo "$EXTRA" | head -5 | tr '\n' ' ')"

PHPBIN=""
for v in lsphp83 lsphp84 lsphp82 lsphp81 lsphp85 lsphp80; do
  [ -x "/usr/local/lsws/$v/bin/php" ] && { PHPBIN="/usr/local/lsws/$v/bin/php"; break; }
done
[ -n "$PHPBIN" ] || done_fail "no lsphp binary found in /usr/local/lsws"
if [ ! -x /usr/local/bin/wp ]; then
  echo "Installing WP-CLI..."
  curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    || done_fail "cannot download WP-CLI"
  chmod 755 /usr/local/bin/wp
fi
WP(){ "$PHPBIN" -d memory_limit=512M /usr/local/bin/wp --allow-root --path="$DIR" "$@"; }

MYSQLBIN="$(command -v mariadb || command -v mysql)"
[ -n "$MYSQLBIN" ] || done_fail "mariadb client not found"
DBROOT="$(cat /etc/cyberpanel/mysqlPassword 2>/dev/null)"
[ -n "$DBROOT" ] || done_fail "cannot read /etc/cyberpanel/mysqlPassword"
SQL(){ "$MYSQLBIN" -uroot -p"$DBROOT" -e "$1"; }

BASE="$(printf '%s' "$DOMAIN" | tr -c 'a-z0-9' '_' | cut -c1-10)"
SUF="$(openssl rand -hex 3)"
DBNAME="wp_${BASE}_${SUF}"; DBUSER="$DBNAME"
DBPASS="$(openssl rand -hex 16)"
WPPASS="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 20)"

if [ "$SCHEME" = "auto" ]; then
  CRT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  SCHEME="http"
  if [ -f "$CRT" ]; then
    ISS="$(openssl x509 -in "$CRT" -noout -issuer 2>/dev/null | sed 's/^issuer=//')"
    SUB="$(openssl x509 -in "$CRT" -noout -subject 2>/dev/null | sed 's/^subject=//')"
    [ -n "$ISS" ] && [ "$ISS" != "$SUB" ] && SCHEME="https"
  fi
fi
URL="$SCHEME://$DOMAIN"
echo "PHP: $PHPBIN   URL: $URL   DB: $DBNAME"

DBCREATED=0
rollback(){
  echo "Rolling back..."
  [ "$DBCREATED" = 1 ] && SQL "DROP DATABASE IF EXISTS \`$DBNAME\`; DROP USER IF EXISTS '$DBUSER'@'localhost';" >/dev/null 2>&1
  [ -e "$DIR/wp-config.php" ] && find "$DIR" -mindepth 1 -maxdepth 1 ! -name '.well-known' ! -name 'cgi-bin' -exec rm -rf {} + 2>/dev/null
  done_fail "$1"
}

echo "[1/6] Creating database..."
SQL "CREATE DATABASE \`$DBNAME\` CHARACTER SET utf8mb4; CREATE USER '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS'; GRANT ALL ON \`$DBNAME\`.* TO '$DBUSER'@'localhost'; FLUSH PRIVILEGES;" \
  || done_fail "cannot create database"
DBCREATED=1

echo "[2/6] Downloading WordPress ($LOCALE)..."
rm -f "$DIR/index.html"
WP core download --locale="$LOCALE" --force 2>&1 || rollback "WordPress download failed"

echo "[3/6] Writing wp-config.php..."
WP config create --dbname="$DBNAME" --dbuser="$DBUSER" --dbpass="$DBPASS" --dbhost=localhost --dbcharset=utf8mb4 --skip-check 2>&1 \
  || rollback "wp config create failed"

echo "[4/6] Installing WordPress..."
WP core install --url="$URL" --title="$TITLE" --admin_user="$WPUSER" --admin_password="$WPPASS" --admin_email="$WPMAIL" --skip-email 2>&1 \
  || rollback "wp core install failed"

echo "[5/6] Finishing (permalinks, plugins)..."
WP rewrite structure '/%postname%/' --hard >/dev/null 2>&1
WP plugin delete hello akismet >/dev/null 2>&1
if [ "$LSCACHE" = "1" ]; then WP plugin install litespeed-cache --activate 2>&1 | tail -2; fi

echo "[6/6] Fixing permissions..."
chown -R "$SITEUSER:$SITEUSER" "$DIR"
chown "$SITEUSER:nogroup" "$DIR"
find "$DIR" -type d -exec chmod 755 {} + 2>/dev/null
find "$DIR" -type f -exec chmod 644 {} + 2>/dev/null
chmod 750 "$DIR"
chmod 640 "$DIR/wp-config.php"

CRED="/root/wp-$DOMAIN.txt"
umask 077
cat > "$CRED" <<EOF
URL:      $URL
Admin:    $URL/wp-admin
Login:    $WPUSER
Password: $WPPASS
DB name:  $DBNAME
DB user:  $DBUSER
DB pass:  $DBPASS
EOF
chmod 600 "$CRED"

echo
echo "=========== DONE ==========="
echo "Site:     $URL"
echo "Admin:    $URL/wp-admin"
echo "Login:    $WPUSER"
echo "Password: $WPPASS"
echo "Saved on the server in: $CRED"
[ "$SCHEME" = "http" ] && echo "NOTE: site uses http. After issuing SSL in CyberPanel run: wp search-replace http://$DOMAIN https://$DOMAIN --path=$DIR --allow-root"
echo "__DONE__ OK"
