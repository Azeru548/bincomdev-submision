#!/usr/bin/env bash
#
# PrestaShop 8.2.x installer for Ubuntu 22.04 LTS with an EXTERNAL MySQL database.
#
# Reads connection/shop settings from /etc/prestashop/app.env, installs Nginx +
# PHP 8.1-FPM, creates the application database user on the remote MySQL host
# (Amazon RDS), unpacks PrestaShop and runs the official CLI installer.
#
# Safe to re-run: if app/config/parameters.php already exists the PHP stack is
# rebuilt but the shop data is left alone.
#
set -Eeuo pipefail

ENV_FILE="${ENV_FILE:-/etc/prestashop/app.env}"
LOG_FILE="${LOG_FILE:-/var/log/prestashop-install.log}"
WEB_ROOT="${WEB_ROOT:-/var/www/html}"
WEB_USER="www-data"
PHP_VER="8.1"
SUMMARY_FILE="/root/prestashop-summary.txt"
INSTALL_BACKUP_DIR="/var/lib/prestashop"
NGINX_SITE="/etc/nginx/sites-available/prestashop"

install -d -m 0755 "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '\n[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'log "FAILED at line $LINENO (exit $?)"' ERR

[[ ${EUID} -eq 0 ]] || die "run as root (sudo)"
[[ -f $ENV_FILE ]] || die "missing env file: $ENV_FILE"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${DB_HOST:?DB_HOST is required}"
DB_PORT="${DB_PORT:-3306}"
: "${DB_NAME:?DB_NAME is required}"
: "${DB_ADMIN_USER:?DB_ADMIN_USER is required}"
: "${DB_ADMIN_PASSWORD:?DB_ADMIN_PASSWORD is required}"
: "${DB_APP_USER:?DB_APP_USER is required}"
: "${DB_APP_PASSWORD:?DB_APP_PASSWORD is required}"
: "${SHOP_NAME:?SHOP_NAME is required}"
: "${ADMIN_EMAIL:?ADMIN_EMAIL is required}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD is required}"
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-Store}"
ADMIN_LASTNAME="${ADMIN_LASTNAME:-Admin}"
SHOP_EMAIL="${SHOP_EMAIL:-$ADMIN_EMAIL}"
TIMEZONE="${TIMEZONE:-UTC}"
COUNTRY="${COUNTRY:-us}"
LANGUAGE="${LANGUAGE:-en}"
PS_VERSION="${PS_VERSION:-8.2.9}"

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------
log "Updating package lists"
export DEBIAN_FRONTEND=noninteractive
for attempt in {1..30}; do
  apt-get update -y && break
  [[ $attempt -eq 30 ]] && die "apt-get update kept failing (no egress?)"
  sleep 10
done

log "Installing Nginx, PHP ${PHP_VER}-FPM, extensions and MySQL client"
apt-get install -y --no-install-recommends \
  nginx unzip curl ca-certificates mysql-client \
  "php${PHP_VER}-fpm" "php${PHP_VER}-cli" "php${PHP_VER}-mysql" "php${PHP_VER}-curl" \
  "php${PHP_VER}-gd" "php${PHP_VER}-intl" "php${PHP_VER}-mbstring" "php${PHP_VER}-xml" \
  "php${PHP_VER}-zip" "php${PHP_VER}-bcmath" "php${PHP_VER}-soap" "php${PHP_VER}-imagick"

# ---------------------------------------------------------------------------
# 2. PHP settings
# ---------------------------------------------------------------------------
log "Writing PHP limits"
for sapi in fpm cli; do
  cat > "/etc/php/${PHP_VER}/${sapi}/conf.d/99-prestashop.ini" <<'PHPINI'
memory_limit = 512M
upload_max_filesize = 32M
post_max_size = 32M
max_execution_time = 120
max_input_vars = 5000
date.timezone = UTC
opcache.enable = 1
opcache.memory_consumption = 128
opcache.max_accelerated_files = 20000
opcache.revalidate_freq = 2
PHPINI
done

systemctl enable --now "php${PHP_VER}-fpm"
systemctl restart "php${PHP_VER}-fpm"

# ---------------------------------------------------------------------------
# 3. Remote database: wait for RDS, then create the app user
# ---------------------------------------------------------------------------
DB_CONN=(-h "$DB_HOST" -P "$DB_PORT" -u "$DB_ADMIN_USER" "-p$DB_ADMIN_PASSWORD" --connect-timeout=5)

log "Waiting for MySQL at ${DB_HOST}:${DB_PORT}"
db_ready=0
for attempt in {1..90}; do
  if mysql "${DB_CONN[@]}" -e 'SELECT 1' >/dev/null 2>&1; then
    db_ready=1
    log "MySQL is reachable on attempt ${attempt}"
    break
  fi
  sleep 10
done
[[ $db_ready -eq 1 ]] || die "cannot reach ${DB_HOST}:${DB_PORT} (check db security group and subnet route table)"

log "Creating database '${DB_NAME}' and user '${DB_APP_USER}' on the remote server"
mysql "${DB_CONN[@]}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_APP_USER}'@'%' IDENTIFIED BY '${DB_APP_PASSWORD}';
ALTER USER '${DB_APP_USER}'@'%' IDENTIFIED BY '${DB_APP_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL

if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_APP_USER" "-p$DB_APP_PASSWORD" "$DB_NAME" -e 'SELECT 1' >/dev/null 2>&1; then
  die "application user ${DB_APP_USER} cannot connect to ${DB_HOST}/${DB_NAME}"
fi
log "Application user verified against the external database"

# ---------------------------------------------------------------------------
# 4. Nginx configuration
# ---------------------------------------------------------------------------
log "Configuring Nginx"
cat > "$NGINX_SITE" <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.php index.html;

    charset utf-8;
    client_max_body_size 32M;

    access_log /var/log/nginx/prestashop.access.log;
    error_log  /var/log/nginx/prestashop.error.log;

    # Never serve the application's internal directories.
    location ~* /(app|bin|config|docs|install|tests|var|vendor|translations)/ { deny all; }
    location ~ /\. { deny all; }

    # Static assets: let PrestaShop's rewrite rules handle anything missing.
    location ~* \.(?:css|js|jpe?g|png|gif|svg|ico|webp|avif|woff2?|ttf|eot|map)$ {
        expires 30d;
        access_log off;
        try_files $uri =404;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { allow all; log_not_found off; access_log off; }

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_read_timeout 120;
    }
}
NGINX

ln -sfn "$NGINX_SITE" /etc/nginx/sites-enabled/prestashop
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# ---------------------------------------------------------------------------
# 5. PrestaShop code
# ---------------------------------------------------------------------------
already_installed=0
[[ -f "$WEB_ROOT/app/config/parameters.php" ]] && already_installed=1

if [[ $already_installed -eq 0 ]]; then
  log "Downloading PrestaShop ${PS_VERSION}"
  work_dir="$(mktemp -d)"
  release_zip="${work_dir}/prestashop_${PS_VERSION}.zip"
  url="https://github.com/PrestaShop/PrestaShop/releases/download/${PS_VERSION}/prestashop_${PS_VERSION}.zip"

  curl -fsSL --retry 3 --retry-delay 5 -o "$release_zip" "$url" \
    || die "download failed: $url"

  # The official release package is a wrapper: it holds prestashop.zip plus a
  # web launcher. Unpack both layers.
  unzip -q "$release_zip" -d "${work_dir}/wrapper"
  if [[ -f "${work_dir}/wrapper/prestashop.zip" ]]; then
    unzip -q "${work_dir}/wrapper/prestashop.zip" -d "${work_dir}/app"
  else
    mkdir -p "${work_dir}/app"
    cp -a "${work_dir}/wrapper/." "${work_dir}/app/"
  fi
  [[ -f "${work_dir}/app/install/index_cli.php" ]] || die "release layout unexpected: install/index_cli.php missing"

  log "Copying files into ${WEB_ROOT}"
  rm -rf "${WEB_ROOT:?}"/* "${WEB_ROOT:?}"/.[!.]* 2>/dev/null || true
  cp -a "${work_dir}/app/." "$WEB_ROOT/"

  log "Setting ownership and permissions"
  chown -R "${WEB_USER}:${WEB_USER}" "$WEB_ROOT"
  find "$WEB_ROOT" -type d -exec chmod 0755 {} +
  find "$WEB_ROOT" -type f -exec chmod 0644 {} +
  for dir in var config app/config img modules themes translations download upload; do
    if [[ -d "${WEB_ROOT}/${dir}" ]]; then
      chmod -R 0775 "${WEB_ROOT}/${dir}"
    fi
  done

  # The shop domain must be the address users type, so take it from instance
  # metadata (Elastic IP public DNS) instead of hard-coding it.
  token="$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300" || true)"
  public_dns="$(curl -s -H "X-aws-ec2-metadata-token: ${token}" \
    http://169.254.169.254/latest/meta-data/public-hostname || true)"
  public_ip="$(curl -s -H "X-aws-ec2-metadata-token: ${token}" \
    http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
  domain="${public_dns:-${public_ip:-localhost}}"
  log "Using shop domain: ${domain}"

  db_server="$DB_HOST"
  [[ "$DB_PORT" != "3306" ]] && db_server="${DB_HOST}:${DB_PORT}"

  log "Running the PrestaShop CLI installer against ${db_server}"
  cd "$WEB_ROOT"
  runuser -u "$WEB_USER" -- "php${PHP_VER}" install/index_cli.php \
    --domain="$domain" \
    --db_server="$db_server" \
    --db_name="$DB_NAME" \
    --db_user="$DB_APP_USER" \
    --db_password="$DB_APP_PASSWORD" \
    --db_create=0 \
    --db_prefix=ps_ \
    --name="$SHOP_NAME" \
    --activity=1 \
    --country="$COUNTRY" \
    --language="$LANGUAGE" \
    --timezone="$TIMEZONE" \
    --firstname="$ADMIN_FIRSTNAME" \
    --lastname="$ADMIN_LASTNAME" \
    --email="$ADMIN_EMAIL" \
    --password="$ADMIN_PASSWORD" \
    --license=0 \
    --rewrite=0 \
    --ssl=0 \
    --fixtures=1

  [[ -f "$WEB_ROOT/app/config/parameters.php" ]] || die "installer finished without writing app/config/parameters.php"

  # The installer leaves a fully privileged installer on the web root; move it
  # outside the document root instead of deleting it, so a retry is possible.
  if [[ -d "$WEB_ROOT/install" ]]; then
    install -d -m 0750 "$INSTALL_BACKUP_DIR"
    mv "$WEB_ROOT/install" "${INSTALL_BACKUP_DIR}/install-backup-$(date -u +%Y%m%dT%H%M%SZ)"
    log "Moved the install directory out of the web root"
  fi

  rm -rf "$work_dir"
else
  log "PrestaShop already installed (app/config/parameters.php present); skipping download and install"
fi

# Re-apply writable permissions after the installer run.
for dir in var config app/config img modules themes translations download upload; do
  [[ -d "${WEB_ROOT}/${dir}" ]] && chmod -R 0775 "${WEB_ROOT}/${dir}"
done
chown -R "${WEB_USER}:${WEB_USER}" "$WEB_ROOT"

# ---------------------------------------------------------------------------
# 6. Summary + smoke test
# ---------------------------------------------------------------------------
admin_dir="$(find "$WEB_ROOT" -maxdepth 1 -type d -name 'admin*' -printf '%f\n' 2>/dev/null | head -n1 || true)"

http_code="000"
for _ in {1..12}; do
  http_code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://127.0.0.1/" || true)"
  [[ "$http_code" == "200" ]] && break
  sleep 5
done

cat > "$SUMMARY_FILE" <<SUMMARY
PrestaShop installation summary
===============================
Store name        : ${SHOP_NAME}
Storefront URL    : http://${domain}/
Back office URL   : http://${domain}/${admin_dir}/  (path is randomised by PrestaShop)
Admin email       : ${ADMIN_EMAIL}
Admin password    : ${ADMIN_PASSWORD}
PrestaShop version: ${PS_VERSION}
PHP version       : $(php -r 'echo PHP_VERSION;')

Database (separate host, Amazon RDS)
  Endpoint        : ${DB_HOST}:${DB_PORT}
  Database        : ${DB_NAME}
  App user        : ${DB_APP_USER}
  Master user     : ${DB_ADMIN_USER}

Installer log     : ${LOG_FILE}
Local HTTP check  : ${http_code}
SUMMARY
chmod 0600 "$SUMMARY_FILE"

log "Local storefront check returned HTTP ${http_code}"
[[ "$http_code" == "200" ]] || log "WARNING: storefront did not return 200 yet; check the Nginx and PHP-FPM logs"
log "Done. Summary written to ${SUMMARY_FILE}"
