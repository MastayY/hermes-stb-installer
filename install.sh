#!/usr/bin/env bash
# install.sh: Main installer entrypoint for Hermes Agent + 9Router Homelab Stack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/detect.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/swap.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/runtime-select.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/podman-setup.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/docker-fix.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/combo-setup.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/healthcheck.sh"

show_help() {
    cat <<EOF
Usage: ./install.sh [OPTIONS]

Installs and configures Hermes Agent and 9Router on low-resource Linux and STB systems.

Options:
  --runtime=podman|docker    Container runtime to use (default: podman)
  --lite                     Enable low-RAM profile (disables browser/vision tools)
  --with-proxy               Deploy Caddy reverse proxy with basicauth and TLS
  --no-swap                  Disable automated swapfile allocation
  --non-interactive          Do not prompt for inputs; rely exclusively on .env
  --help, -h                 Display this help message

Examples:
  ./install.sh
  ./install.sh --lite
  ./install.sh --runtime=docker --no-swap
EOF
}

# Default flag values
REQUESTED_RUNTIME="podman"
LITE_MODE=false
WITH_PROXY=false
NO_SWAP=false
NON_INTERACTIVE=false

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --runtime=*)
            REQUESTED_RUNTIME="${1#*=}"
            shift
            ;;
        --lite)
            LITE_MODE=true
            shift
            ;;
        --with-proxy)
            WITH_PROXY=true
            shift
            ;;
        --no-swap)
            NO_SWAP=true
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
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
echo "    Hermes Agent + 9Router Homelab STB Installer         "
echo "=========================================================="

# -----------------------------------------------------------------------------
# Step 1: Preflight Detection
# -----------------------------------------------------------------------------
echo "[1/7] Running preflight system inspection..."
run_preflight_checks

# Auto-enable lite mode if RAM is <= 2048 MB and user did not specify
if [[ "${DETECT_IS_LOW_RAM}" == "true" && "${LITE_MODE}" != "true" ]]; then
    echo "NOTICE: Low physical RAM detected (${DETECT_RAM_MB} MB). Automatically activating --lite mode."
    LITE_MODE=true
fi

# -----------------------------------------------------------------------------
# Step 2: Swap Management
# -----------------------------------------------------------------------------
echo "[2/7] Checking memory and swap configuration..."
swap_setup "${DETECT_RAM_MB}" "${NO_SWAP}"

# -----------------------------------------------------------------------------
# Step 3: Runtime Resolution and Setup
# -----------------------------------------------------------------------------
echo "[3/7] Setting up container runtime..."
RUNTIME="$(runtime_determine "${REQUESTED_RUNTIME}")"
echo "Selected runtime: ${RUNTIME}"

runtime_install_package "${RUNTIME}"
runtime_save_state "${RUNTIME}"

if [[ "${RUNTIME}" == "podman" ]]; then
    podman_enable_user_linger "$(whoami)"
    podman_verify_subuid_subgid "$(whoami)"
elif [[ "${RUNTIME}" == "docker" ]]; then
    docker_apply_daemon_json
    docker_apply_ufw_rules
fi

# -----------------------------------------------------------------------------
# Step 4: Environment & Secrets Preparation
# -----------------------------------------------------------------------------
echo "[4/7] Preparing environment variables and configuration files..."
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Creating new .env from template..."
    cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"

    # Generate secure random secret for 9Router JWT
    random_secret="$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || openssl rand -hex 32 2>/dev/null || echo "random_secret_$(date +%s)")"
    sed -i "s|^ROUTER_JWT_SECRET=.*|ROUTER_JWT_SECRET=${random_secret}|" "${ENV_FILE}"

    # Set user UID and GID
    current_uid="$(id -u)"
    current_gid="$(id -g)"
    sed -i "s|^HERMES_UID=.*|HERMES_UID=${current_uid}|" "${ENV_FILE}"
    sed -i "s|^HERMES_GID=.*|HERMES_GID=${current_gid}|" "${ENV_FILE}"

    # Secure file permissions (0600)
    chmod 600 "${ENV_FILE}"
    echo "Generated ${ENV_FILE} with restrictive permissions (0600)."
fi

# Prepare Hermes config directory and configuration file
HERMES_HOST_DIR="${HERMES_DATA_DIR:-${HOME}/.hermes}"
HERMES_HOST_DIR="${HERMES_HOST_DIR/#\~/$HOME}"

if mkdir -p "${HERMES_HOST_DIR}" 2>/dev/null; then
    if [[ -w "${HERMES_HOST_DIR}" ]]; then
        if [[ ! -f "${HERMES_HOST_DIR}/config.yaml" ]]; then
            cp "${SCRIPT_DIR}/config/hermes-config.template.yaml" "${HERMES_HOST_DIR}/config.yaml" 2>/dev/null || true
            chmod 644 "${HERMES_HOST_DIR}/config.yaml" 2>/dev/null || true
        fi
    else
        echo "Notice: ${HERMES_HOST_DIR} is owned by another UID (likely container user). Skipping template copy."
    fi
fi

# Prepare Caddyfile if proxy is enabled
if [[ "${WITH_PROXY}" == "true" ]]; then
    if [[ ! -f "${SCRIPT_DIR}/config/Caddyfile" ]]; then
        cp "${SCRIPT_DIR}/config/Caddyfile.template" "${SCRIPT_DIR}/config/Caddyfile"
    fi
fi

# -----------------------------------------------------------------------------
# Step 5: Service Deployment
# -----------------------------------------------------------------------------
echo "[5/7] Deploying containers..."

COMPOSE_ARGS=("-f")
COMPOSE_PRIMARY_FILE="compose/docker-compose.yml"
if [[ "${LITE_MODE}" == "true" ]]; then
    COMPOSE_PRIMARY_FILE="compose/docker-compose.lite.yml"
fi
COMPOSE_ARGS+=("${SCRIPT_DIR}/${COMPOSE_PRIMARY_FILE}")

if [[ "${WITH_PROXY}" == "true" ]]; then
    COMPOSE_ARGS+=("-f" "${SCRIPT_DIR}/compose/docker-compose.proxy.yml")
fi

# Export environment file variables for compose execution
# shellcheck disable=SC2046
export $(grep -v '^#' "${ENV_FILE}" | xargs -d '\n' 2>/dev/null || true)

if [[ "${RUNTIME}" == "podman" ]]; then
    podman_setup_systemd_service "${SCRIPT_DIR}" "${COMPOSE_PRIMARY_FILE}"
fi

echo "Starting services via ${RUNTIME} compose..."
container_compose_exec "${RUNTIME}" "${COMPOSE_ARGS[@]}" up -d

# -----------------------------------------------------------------------------
# Step 6: 9Router Provider & Combo Registration
# -----------------------------------------------------------------------------
echo "[6/7] Initializing 9Router provider and fallback combo routing..."
if combo_wait_for_router 20 2; then
    combo_run_autoconfig "${ENV_FILE}"
else
    echo "NOTICE: 9Router took longer than expected to start. You can rerun './lib/combo-setup.sh' later."
fi

# -----------------------------------------------------------------------------
# Step 7: Post-Install Health Diagnostics
# -----------------------------------------------------------------------------
echo "[7/7] Running post-installation diagnostics..."
run_full_healthcheck "${RUNTIME}"

# -----------------------------------------------------------------------------
# Final Summary and Instructions
# -----------------------------------------------------------------------------
local_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_STB_IP")"

echo "=========================================================="
echo "          Installation Successfully Completed!           "
echo "=========================================================="
echo "Active Runtime      : ${RUNTIME}"
echo "Deployment Profile  : $([[ "${LITE_MODE}" == "true" ]] && echo "Lite (RAM-optimized)" || echo "Standard")"
echo "Reverse Proxy       : $([[ "${WITH_PROXY}" == "true" ]] && echo "Enabled (Caddy TLS)" || echo "Disabled (Internal only)")"
echo ""
echo "Accessing 9Router Web Dashboard:"
echo "  Direct Local LAN  : http://127.0.0.1:20128/dashboard"
echo "  Via SSH Tunnel    : ssh -L 20128:127.0.0.1:20128 $(whoami)@${local_ip}"
echo "                      Then open http://localhost:20128/dashboard in your local browser."
echo ""
echo "Connecting Hermes Agent:"
echo "  1. If you provided TELEGRAM_BOT_TOKEN in .env, start chatting with your bot on Telegram."
echo "  2. If not yet configured, edit .env with your bot token and run: ./update.sh"
echo ""
echo "Management Commands:"
echo "  Update stack      : ./update.sh $([[ "${LITE_MODE}" == "true" ]] && echo "--lite")"
echo "  View router logs  : ${RUNTIME} logs -f 9router"
echo "  View agent logs   : ${RUNTIME} logs -f hermes-agent"
echo "  Uninstall stack   : ./uninstall.sh"
echo "=========================================================="
