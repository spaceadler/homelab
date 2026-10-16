#!/usr/bin/env bash
# Vaultwarden's site depends on how HTTPS is provided:
#   HTTP mode   tailscale serve owns https://<machine>.<tailnet>.ts.net (the
#               VAULT_HOST); vault.<DOMAIN> just redirects there.
#   HTTPS mode  your own certificate covers vault.<DOMAIN> (now VAULT_HOST),
#               so nginx serves it like any other app.
set -euo pipefail

site=$HOMELAB_SITES/vaultwarden.conf
if [ "$URL_SCHEME" = https ]; then
    cat >"$site" <<'EOF'
# Vaultwarden → https://vault.<domain> (HTTPS mode)
server {
    include snippets/listen.conf;
    server_name vault.*;
    location / {
        proxy_pass http://127.0.0.1:4345;
        include snippets/proxy.conf;
    }
}
EOF
else
    cat >"$site" <<EOF
# vault.<domain> → the HTTPS address tailscale serve provides (HTTP mode)
server {
    include snippets/listen.conf;
    server_name vault.*;
    return 301 https://$VAULT_HOST\$request_uri;
}
EOF
fi
