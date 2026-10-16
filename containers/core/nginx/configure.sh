#!/usr/bin/env bash
# HTTP or HTTPS for every app at once. install.sh sets URL_SCHEME=https when a
# certificate for DOMAIN exists in ./letsencrypt (see docs/tls.md). Each site
# includes snippets/listen.conf instead of writing its own listen line, so
# this one file decides for all of them.
set -euo pipefail

if [ "$URL_SCHEME" = https ]; then
    cat >snippets/listen.conf <<EOF
# HTTPS mode (written by configure.sh from your certificate).
listen 443 ssl;
http2 on;
ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
EOF
    cat >"$HOMELAB_SITES/00-https.conf" <<EOF
# HTTPS mode (written by configure.sh). Plain HTTP for your domain redirects;
# HTTPS for a name that isn't an app is refused during the handshake.
server {
    listen 80;
    server_name .$DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl default_server;
    ssl_reject_handshake on;
}
EOF
else
    printf '# HTTP mode (written by configure.sh; see docs/tls.md for HTTPS).\nlisten 80;\n' \
        >snippets/listen.conf
fi
