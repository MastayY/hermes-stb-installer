#!/usr/bin/env bash
# uninstall.sh — hermes-9router-stb-installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: uninstall.sh needs root. Re-run with sudo." >&2
  exit 1
fi

# shellcheck source=lib/swap.sh
. lib/swap.sh
# shellcheck source=lib/runtime-select.sh
. lib/runtime-select.sh
# shellcheck source=lib/podman-setup.sh
. lib/podman-setup.sh
# shellcheck source=lib/docker-fix.sh
. lib/docker-fix.sh

if [ ! -f .runtime ]; then
  echo "ERROR: .runtime state file not found — was this installed with" >&2
  echo "       install.sh from this same directory?" >&2
  exit 1
fi
CONTAINER_RUNTIME="$(cat .runtime)"
export CONTAINER_RUNTIME
WITH_PROXY=0
[ -f config/Caddyfile ] && WITH_PROXY=1
export WITH_PROXY

echo "This will stop and remove the hermes + 9router containers, revert"
echo "runtime-level system changes (UFW rule or podman-restart service),"
echo "and optionally remove the swapfile and all data (chat history,"
echo "provider keys, combo config)."
echo
read -r -p "Remove all data in ./data too? [y/N] " remove_data
read -r -p "Remove swapfile created by install.sh (if any)? [y/N] " remove_swap_answer
read -r -p "Proceed with uninstall? [y/N] " confirm

if [ "${confirm,,}" != "y" ]; then
  echo "Aborted."
  exit 0
fi

echo "Stopping and removing containers..."
compose down --remove-orphans || true

if [ "$CONTAINER_RUNTIME" = "podman" ]; then
  teardown_podman_rootless_autostart
else
  revert_docker_ufw_fix
fi

if [ "${remove_swap_answer,,}" = "y" ]; then
  remove_swap
fi

if [ "${remove_data,,}" = "y" ]; then
  rm -rf data
  rm -f .env config/Caddyfile
  echo "Removed ./data, .env, config/Caddyfile"
fi

rm -f .runtime

echo "Uninstall complete."
