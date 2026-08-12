#!/bin/bash
set -euo pipefail

# --- config ---
USER_NAME="YOUR_USERNAME"
USER_HOME="/home/$USER_NAME"
ROOT_DIR="$USER_HOME/homelab/containers"
TEMP_BASE="$USER_HOME/homelab/backup/containers"

BACKUP_DATE="$(date +%F)"
TEMP_DIR="$TEMP_BASE/$BACKUP_DATE"
# --------------

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)."
    exit 1
fi

echo "📁 Creating backup directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo "🔍 Searching for docker-compose files..."
mapfile -t COMPOSE_DIRS < <(
    find "$ROOT_DIR" -type f \( -name docker-compose.yml -o -name compose.yml \) \
        -exec dirname {} \; | sort -u
)

echo "🛑 Stopping containers..."
for dir in "${COMPOSE_DIRS[@]}"; do
    (cd "$dir" && docker compose down)
done

echo "📦 Backing up data (preserving exact permissions)..."
rsync -a "$ROOT_DIR/" "$TEMP_DIR/"

echo "🚀 Restarting containers..."
for dir in "${COMPOSE_DIRS[@]}"; do
    (cd "$dir" && docker compose up -d)
done
echo "✅ Backup complete!"
