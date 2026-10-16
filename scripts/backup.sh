#!/bin/bash
# Layer 1 backup: stop every running stack, copy containers/ (configs, .env
# secrets and app data) to backup/containers/<date>, start them again.
# Stopping first is what makes the database files consistent; expect the
# lab to be offline while it runs.
#
#   sudo ./scripts/backup.sh
set -euo pipefail

# --- config ---
HOMELAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$HOMELAB/containers"
TEMP_BASE="$HOMELAB/backup/containers"

BACKUP_DATE="$(date +%F)"
TEMP_DIR="$TEMP_BASE/$BACKUP_DATE"
# --------------

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)."
    exit 1
fi

echo "📁 Creating backup directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
chmod 700 "$TEMP_BASE" # the copy holds every app's secrets

echo "🔍 Finding running stacks..."
# Only stacks with running containers: the repo has a folder for every app,
# and starting one you never installed would fail on its missing .env.
COMPOSE_DIRS=()
while IFS= read -r dir; do
    if [ -n "$(cd "$dir" && docker compose ps -q 2>/dev/null)" ]; then
        COMPOSE_DIRS+=("$dir")
    fi
done < <(find "$ROOT_DIR" -type f \( -name docker-compose.yml -o -name compose.yml \) \
    -exec dirname {} \; | sort -u)
echo "   ${#COMPOSE_DIRS[@]} running"

echo "🛑 Stopping containers..."
for dir in "${COMPOSE_DIRS[@]}"; do
    (cd "$dir" && docker compose down)
done

echo "📦 Backing up data (preserving exact permissions)..."
rsync -a "$ROOT_DIR/" "$TEMP_DIR/"

echo "🚀 Restarting containers..."
for dir in "${COMPOSE_DIRS[@]}"; do
    (cd "$dir" && docker compose up -d) || echo "⚠️  failed to restart $dir"
done
echo "✅ Backup complete!"
