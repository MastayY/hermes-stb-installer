#!/usr/bin/env bash
# update.sh: Pull latest container images and restart services without data loss.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/runtime-select.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/healthcheck.sh"

show_help() {
    cat <<EOF
Usage: ./update.sh [OPTIONS]

Pulls the latest container images for 9Router and Hermes Agent,
and gracefully restarts the stack without altering configuration.

Options:
  --lite             Use the lite mode compose specification
  --with-proxy       Include the Caddy reverse proxy override
  --help, -h         Display this help message

EOF
}

LITE_MODE=false
WITH_PROXY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lite)
            LITE_MODE=true
            shift
            ;;
        --with-proxy)
            WITH_PROXY=true
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

echo "=========================================================="
echo "           Hermes + 9Router Stack Updater                 "
echo "=========================================================="

RUNTIME="$(runtime_determine "")"
echo "Active runtime: ${RUNTIME}"

COMPOSE_ARGS=("-f")
if [[ "${LITE_MODE}" == "true" ]]; then
    COMPOSE_ARGS+=("${SCRIPT_DIR}/compose/docker-compose.lite.yml")
else
    COMPOSE_ARGS+=("${SCRIPT_DIR}/compose/docker-compose.yml")
fi

if [[ "${WITH_PROXY}" == "true" ]]; then
    COMPOSE_ARGS+=("-f" "${SCRIPT_DIR}/compose/docker-compose.proxy.yml")
fi

echo "Pulling updated container images..."
container_compose_exec "${RUNTIME}" "${COMPOSE_ARGS[@]}" pull

echo "Recreating and restarting updated services..."
container_compose_exec "${RUNTIME}" "${COMPOSE_ARGS[@]}" up -d --remove-orphans

echo "Verifying service health after update..."
run_full_healthcheck "${RUNTIME}"

echo "=========================================================="
echo "Update completed successfully."
echo "=========================================================="
