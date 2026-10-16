#!/usr/bin/env bash
# Start the agent once the hub has made its key pair. The hub writes only the
# private key; the agent's KEY is the matching public key, which ssh-keygen
# derives from it.
set -euo pipefail

key=beszel_data/id_ed25519
for _ in $(seq 60); do
    sudo test -f "$key" && break
    sleep 1
done
if ! sudo test -f "$key"; then
    echo "  ! The Beszel hub hasn't written $key yet; re-run ./install.sh in a minute."
    exit 0
fi

if [ ! -s agent/.env ]; then
    printf 'BESZEL_AGENT_KEY="%s"\n' "$(sudo ssh-keygen -y -f "$key")" > agent/.env
    chmod 600 agent/.env
fi
(cd agent && $DOCKER compose up -d)
echo "  In Beszel: Add System → host host.docker.internal, port 45876."
