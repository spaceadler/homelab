#!/bin/bash
# Renew the HTTPS-mode certificate (see docs/tls.md) and reload nginx.
# certbot only renews within 30 days of expiry, so running this daily is
# cheap; most days it does nothing. For cron:
#
#   0 3 * * * /home/<you>/homelab/scripts/renew-certs.sh >/dev/null
set -euo pipefail

NGINX="$(cd "$(dirname "${BASH_SOURCE[0]}")/../containers/core/nginx" && pwd)"
DOCKER=docker
docker info >/dev/null 2>&1 || DOCKER="sudo docker"

$DOCKER run --rm \
    -v "$NGINX/letsencrypt:/etc/letsencrypt" \
    -v "$NGINX/certbot:/certbot:ro" \
    certbot/dns-cloudflare renew --quiet
$DOCKER exec nginx nginx -s reload
