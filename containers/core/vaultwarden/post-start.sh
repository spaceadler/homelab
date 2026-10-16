#!/usr/bin/env bash
# HTTP mode: HTTPS for Vaultwarden comes from `tailscale serve`, which
# terminates TLS on this machine's tailnet name and proxies to
# 127.0.0.1:4345. It is tailnet-only (`funnel` would be the internet), and
# Tailscale issues and renews the certificate itself. If HTTPS certificates
# aren't enabled for your tailnet yet, tailscale prints a link to enable them
# and waits; open it and this carries on.
#
# HTTPS mode: nginx serves vault.<DOMAIN> on port 443, which tailscale serve
# would intercept, so it's switched off.
set -euo pipefail

serving() { sudo tailscale serve status 2>/dev/null | grep -q '127.0.0.1:4345'; }

if [ "$URL_SCHEME" = https ]; then
    if serving; then
        sudo tailscale serve --https=443 off
        echo "  tailscale serve turned off: nginx serves https://$VAULT_HOST now"
    fi
    exit 0
fi

if serving; then
    echo "  https://$VAULT_HOST already serves Vaultwarden"
elif sudo tailscale serve --bg --https=443 http://127.0.0.1:4345; then
    echo "  https://$VAULT_HOST now serves Vaultwarden"
else
    cat <<'EOF'
  ! tailscale serve failed. Check that MagicDNS and HTTPS Certificates are
    enabled (Tailscale admin console → DNS), then re-run ./install.sh.
EOF
fi
