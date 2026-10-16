#!/usr/bin/env bash
# Syncthing starts with no GUI login. Before the first start, generate its
# config with one, using the image's own `syncthing generate` (which stores
# the password bcrypt-hashed). An existing config is left alone.
set -euo pipefail

[ -f config/config.xml ] && exit 0
mkdir -p config
$DOCKER run --rm --user "$PUID:$PGID" -v "$PWD/config:/config" \
    --entrypoint syncthing lscr.io/linuxserver/syncthing:latest \
    generate --home=/config \
    --gui-user="$SYNCTHING_GUI_USER" --gui-password="$SYNCTHING_GUI_PASSWORD" >/dev/null
