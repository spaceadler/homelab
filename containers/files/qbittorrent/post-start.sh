#!/usr/bin/env bash
# Show qBittorrent's first-run temporary password (only printed once a fresh
# config is created; nothing to show after you've set your own).
for _ in $(seq 20); do
    line=$($DOCKER logs qbittorrent 2>&1 | grep -i 'temporary password' | tail -1)
    [ -n "$line" ] && break
    sleep 1
done
[ -n "$line" ] && echo "  qBittorrent web UI: user admin, ${line##*: }"
exit 0
