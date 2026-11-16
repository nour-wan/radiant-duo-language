#!/bin/sh
# Daily backup of the Alas API database and uploaded images. Keeps 14 days.
# Installed as /etc/cron.d/alas-api-backup (runs as root at 03:30).
set -eu
DEST=/var/backups/alas-api
STAMP=$(date +%Y%m%d-%H%M)
mkdir -p "$DEST"
chmod 700 "$DEST"
sudo -u postgres pg_dump --format=custom alas > "$DEST/db-$STAMP.dump"
tar -czf "$DEST/media-$STAMP.tar.gz" -C /var/lib/alas-api media
find "$DEST" -type f -mtime +14 -delete
