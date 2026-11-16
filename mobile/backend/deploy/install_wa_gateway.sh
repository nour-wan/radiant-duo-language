#!/bin/bash
# WhatsApp gateway for verification codes. Only ADDS: user alaswa, group alaswakey,
# /opt/alas-wa, /var/lib/alas-wa, /etc/alas-wa and the alas-wa systemd service (port 8110, localhost).
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/wa_gateway"
APP=/opt/alas-wa

echo "==> WhatsApp gateway"
id alaswa >/dev/null 2>&1 || useradd --system --home /var/lib/alas-wa --shell /usr/sbin/nologin alaswa
# The API reads the shared key through this group
getent group alaswakey >/dev/null || groupadd --system alaswakey
usermod -aG alaswakey alaswa
usermod -aG alaswakey alasapi

install -d -o alaswa -g alaswa -m 700 /var/lib/alas-wa
install -d -o root -g alaswakey -m 750 /etc/alas-wa
if [ ! -f /etc/alas-wa/key ]; then
  openssl rand -hex 32 > /etc/alas-wa/key
  echo "    created /etc/alas-wa/key"
fi
chown root:alaswakey /etc/alas-wa/key
chmod 640 /etc/alas-wa/key

install -d -o root -g root -m 755 "$APP"
rsync -a --exclude node_modules "$SRC/" "$APP/"
(cd "$APP" && npm install --omit=dev --no-audit --no-fund --loglevel=error)
chown -R root:root "$APP"

install -m 644 "$SRC/../deploy/alas-wa.service" /etc/systemd/system/alas-wa.service
systemctl daemon-reload
systemctl enable -q alas-wa.service
systemctl restart alas-wa.service
