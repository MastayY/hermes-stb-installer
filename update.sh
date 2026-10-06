#!/usr/bin/env bash
# update.sh — hermes-stb-installer
# Pulls new images and recreates containers without touching .env or data/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .runtime ]; then
  echo "ERROR: .runtime state file not found — run install.sh first." >&2
  exit 1
fi
CONTAINER_RUNTIME="$(cat .runtime)"
export CONTAINER_RUNTIME
WITH_PROXY=0
[ -f config/Caddyfile ] && WITH_PROXY=1
export WITH_PROXY

# shellcheck source=lib/runtime-select.sh
. lib/runtime-select.sh

echo "Backing up ./data and .env before updating..."
backup_dir="backups/$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
cp -a .env "$backup_dir/" 2>/dev/null || true
cp -a data "$backup_dir/" 2>/dev/null || true
echo "  Backup at $backup_dir"

echo "Pulling latest images..."
compose pull

echo "Recreating containers..."
compose up -d --force-recreate

echo "Done. Check status with: $CONTAINER_RUNTIME ps"
