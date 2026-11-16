#!/bin/bash
# Install or update the Alas API on Ubuntu 24.04. Run as root from the extracted
# source folder:  sudo bash deploy/install.sh
#
# Only ADDS things: a new system user, a new PostgreSQL database, /opt/alas-api,
# /var/lib/alas-api, /etc/alas-api, a new systemd service and a new Nginx site.
# It never edits other Nginx sites, services, databases or Docker containers.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP=/opt/alas-api
DATA=/var/lib/alas-api
ETC=/etc/alas-api
DOMAIN=api.alasfoodstuff.com

echo "==> Packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql python3-venv rsync >/dev/null

echo "==> System user"
id alasapi >/dev/null 2>&1 || useradd --system --home "$DATA" --shell /usr/sbin/nologin alasapi

echo "==> Folders"
install -d -o root -g root -m 755 "$APP"
install -d -o alasapi -g alasapi -m 755 "$DATA" "$DATA/media"
chmod -R a+rX "$DATA/media"
# APKs for /download/ — uploaded by root, served read-only by Nginx
install -d -o root -g root -m 755 "$DATA/downloads"
install -d -o root -g alasapi -m 750 "$ETC"

echo "==> Code (code is owned by root and read-only for the app user)"
rsync -a --delete --exclude .venv --exclude media --exclude staticfiles --exclude db.sqlite3 --exclude .env \
  --exclude __pycache__ "$SRC/" "$APP/"
chown -R root:root "$APP"

echo "==> PostgreSQL (local only)"
if [ ! -f "$ETC/env" ]; then
  DB_PASS=$(openssl rand -hex 24)
  SECRET=$(openssl rand -base64 48 | tr -d '\n/+=')
  sudo -u postgres psql -qtAc "SELECT 1 FROM pg_roles WHERE rolname='alas'" | grep -q 1 || \
    sudo -u postgres psql -qc "CREATE ROLE alas LOGIN PASSWORD '$DB_PASS'"
  sudo -u postgres psql -qtAc "SELECT 1 FROM pg_database WHERE datname='alas'" | grep -q 1 || \
    sudo -u postgres psql -qc "CREATE DATABASE alas OWNER alas ENCODING 'UTF8' TEMPLATE template0"
  sed -e "s|^DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=$SECRET|" \
      -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" \
      "$APP/.env.example" > "$ETC/env"
  chown root:alasapi "$ETC/env"
  chmod 640 "$ETC/env"
  echo "    created $ETC/env with random secrets"
fi

echo "==> Python environment"
[ -d "$APP/.venv" ] || python3 -m venv "$APP/.venv"
"$APP/.venv/bin/pip" install -q --upgrade pip
"$APP/.venv/bin/pip" install -q -r "$APP/requirements.txt"

run_manage() { sudo -u alasapi bash -c "set -a; . $ETC/env; set +a; cd $APP && $APP/.venv/bin/python manage.py $*"; }
echo "==> Migrate, static files, seed data"
install -d -o alasapi -g alasapi "$APP/staticfiles"
run_manage migrate --noinput
run_manage collectstatic --noinput -v0
chown -R root:root "$APP/staticfiles"
run_manage seed_store

bash "$SRC/deploy/install_wa_gateway.sh"

echo "==> systemd service"
install -m 644 "$APP/deploy/alas-api.service" /etc/systemd/system/alas-api.service
systemctl daemon-reload
systemctl enable -q alas-api.service
systemctl restart alas-api.service

echo "==> Nginx site (new file)"
if [ ! -f /etc/nginx/sites-available/$DOMAIN ]; then
  install -m 644 "$APP/deploy/$DOMAIN.nginx" /etc/nginx/sites-available/$DOMAIN
  ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
fi
nginx -t && systemctl reload nginx

echo "==> Backups"
install -m 755 "$APP/deploy/backup.sh" /usr/local/sbin/alas-api-backup
echo "30 3 * * * root /usr/local/sbin/alas-api-backup" > /etc/cron.d/alas-api-backup

sleep 2
curl -fsS -H "Host: $DOMAIN" http://127.0.0.1/health/ && echo "  <- API health OK"
if [ ! -d /etc/letsencrypt/live/$DOMAIN ]; then
  echo "Done. Next: certbot --nginx -d $DOMAIN --redirect  (once the DNS A record points to this server)"
else
  echo "Done."
fi
