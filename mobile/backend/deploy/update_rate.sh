#!/bin/sh
# Reads today's USD rate (Damascus) from sp-today.com for the store's Syrian-pound prices.
# Installed as /usr/local/sbin/alas-api-rate, run every 15 minutes from /etc/cron.d/alas-api-rate.
set -eu
cd /opt/alas-api
exec sudo -u alasapi sh -c 'set -a; . /etc/alas-api/env; set +a; exec /opt/alas-api/.venv/bin/python manage.py update_exchange_rate' \
  >> /var/log/alas-api-rate.log 2>&1
