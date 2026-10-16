#!/usr/bin/env bash
# Vaultwarden is only reachable over HTTPS on this machine's tailnet name, so
# without one there is nothing to serve it on yet.
if [ -z "${VAULT_HOST:-}" ]; then
    cat <<'EOF'
  Vaultwarden needs this machine's Tailscale name (MagicDNS) for HTTPS.
  Tailscale admin console → DNS → enable MagicDNS and HTTPS Certificates,
  then re-run ./install.sh.
EOF
    exit 10
fi
