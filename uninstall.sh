#!/usr/bin/env bash
# uninstall.sh: Clean teardown and uninstaller for Hermes Agent + 9Router Homelab Stack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/runtime-select.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/podman-setup.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/docker-fix.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/swap.sh"

show_help() {
    cat <<EOF
Usage: ./uninstall.sh [OPTIONS]

Cleanly stops and tears down the Hermes Agent + 9Router stack.

Options:
  --purge-data       Delete persistent data directories (~/.hermes and ~/.9router)
  --remove-swap      Deactivate and remove /swapfile created during installation
  --force, -f        Execute without interactive confirmation prompts
  --help, -h         Display this help message

EOF
}

PURGE_DATA=false
REMOVE_SWAP=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge-data)
            PURGE_DATA=true
            shift
            ;;
        --remove-swap)
            REMOVE_SWAP=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

if [[ "${FORCE}" != "true" && -t 0 ]]; then
    read -r -p "Are you sure you want to uninstall Hermes Agent + 9Router? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
fi

echo "=========================================================="
echo "          Hermes + 9Router Stack Uninstaller             "
echo "=========================================================="

RUNTIME="$(runtime_determine "")"
echo "Active runtime identified: ${RUNTIME}"

# 1. Stop and remove containers
echo "Stopping container services..."
if [[ -f "${SCRIPT_DIR}/compose/docker-compose.yml" ]]; then
    container_compose_exec "${RUNTIME}" -f "${SCRIPT_DIR}/compose/docker-compose.yml" down --remove-orphans 2>/dev/null || true
fi
if [[ -f "${SCRIPT_DIR}/compose/docker-compose.lite.yml" ]]; then
    container_compose_exec "${RUNTIME}" -f "${SCRIPT_DIR}/compose/docker-compose.lite.yml" down --remove-orphans 2>/dev/null || true
fi

# 2. Runtime-specific cleanups
if [[ "${RUNTIME}" == "podman" ]]; then
    echo "Removing Podman systemd autostart service..."
    podman_remove_systemd_service
elif [[ "${RUNTIME}" == "docker" ]]; then
    echo "Reverting Docker UFW firewall rules..."
    docker_revert_ufw_rules
fi

# 3. Swapfile cleanup (if requested)
if [[ "${REMOVE_SWAP}" == "true" ]]; then
    echo "Removing allocated swapfile..."
    swap_remove
fi

# 4. Data purge (if requested)
if [[ "${PURGE_DATA}" == "true" ]]; then
    echo "Purging application data directories..."
    rm -rf "${HOME}/.hermes" "${HOME}/.9router"
    echo "Data directories removed."
else
    echo "Preserving configuration and data directories (~/.hermes and ~/.9router)."
fi

# 5. Remove state file
rm -f "${SCRIPT_DIR}/.runtime"

echo "=========================================================="
echo "Uninstall completed cleanly."
echo "=========================================================="
