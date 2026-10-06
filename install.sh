#!/usr/bin/env bash
# install.sh — hermes-stb-installer
#
# curl -fsSL <raw-url>/install.sh | bash
# (or, safer: download first, read it, then run — see docs/README.md)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# -----------------------------------------------------------------------------
# Flag parsing
# -----------------------------------------------------------------------------
RUNTIME_CHOICE="podman"
NO_SWAP=0
WITH_PROXY=0
PROXY_DOMAIN=""

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --runtime=podman|docker   Container runtime to use (default: podman)
  --no-swap                 Skip automatic swapfile creation
  --with-proxy=<domain>     Also set up Caddy reverse proxy for 9router's
                             dashboard at <domain> (off by default)
  -h, --help                Show this help and exit
EOF
}

for arg in "$@"; do
  case "$arg" in
    --runtime=*) RUNTIME_CHOICE="${arg#*=}" ;;
    --no-swap) NO_SWAP=1 ;;
    --with-proxy=*) WITH_PROXY=1; PROXY_DOMAIN="${arg#*=}" ;;
    --with-proxy) echo "ERROR: --with-proxy requires a domain, e.g. --with-proxy=hermes.example.com" >&2; exit 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option '$arg'" >&2; usage; exit 1 ;;
  esac
done
export NO_SWAP WITH_PROXY

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: install.sh needs root (for package install, swap, UFW/systemd" >&2
  echo "       changes). Re-run with sudo: sudo ./install.sh $*" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Load libraries
# -----------------------------------------------------------------------------
# shellcheck source=lib/detect.sh
. lib/detect.sh
# shellcheck source=lib/swap.sh
. lib/swap.sh
# shellcheck source=lib/runtime-select.sh
. lib/runtime-select.sh
# shellcheck source=lib/podman-setup.sh
. lib/podman-setup.sh
# shellcheck source=lib/docker-fix.sh
. lib/docker-fix.sh
# shellcheck source=lib/combo-setup.sh
. lib/combo-setup.sh
# shellcheck source=lib/healthcheck.sh
. lib/healthcheck.sh

echo "=================================================================="
echo " hermes-stb-installer"
echo "=================================================================="

# -----------------------------------------------------------------------------
# Phase 1 — Preflight
# -----------------------------------------------------------------------------
echo
echo "[1/9] Preflight checks"
detect_arch
detect_ram_mb
detect_distro
print_detect_summary
require_supported_arch

# -----------------------------------------------------------------------------
# Phase 2 — Resource management (swap)
# -----------------------------------------------------------------------------
echo
echo "[2/9] Resource management"
ensure_swap "$RAM_TOTAL_MB" "${SWAP_THRESHOLD_MB:-2048}"

# -----------------------------------------------------------------------------
# Phase 3 — Runtime setup
# -----------------------------------------------------------------------------
echo
echo "[3/9] Container runtime ($RUNTIME_CHOICE)"
select_runtime "$RUNTIME_CHOICE"
smoke_test_runtime

if [ "$CONTAINER_RUNTIME" = "podman" ]; then
  setup_podman_rootless_autostart
else
  apply_docker_ufw_fix
  apply_docker_log_rotation
fi

# -----------------------------------------------------------------------------
# Phase 4 — .env
# -----------------------------------------------------------------------------
echo
echo "[4/9] Configuration (.env)"
if [ ! -f .env ]; then
  if [ -t 0 ]; then
    cp .env.example .env
    echo "  .env created from .env.example — edit it now with your API keys"
    echo "  and Telegram bot token, then press Enter to continue (or Ctrl+C"
    echo "  to stop and edit at your leisure, then re-run ./install.sh)."
    read -r _ || true
  else
    echo "ERROR: .env not found and this isn't an interactive terminal" >&2
    echo "       (e.g. running via curl | bash). Create .env from" >&2
    echo "       .env.example first, then re-run." >&2
    exit 1
  fi
fi
# shellcheck source=.env.example
set -a
. ./.env
set +a

# -----------------------------------------------------------------------------
# Phase 5 — Data dirs + Hermes config.yaml
# -----------------------------------------------------------------------------
echo
echo "[5/9] Preparing data directories"
mkdir -p data/9router data/hermes data/caddy/data data/caddy/config

write_service_env_files() {
  # Split .env so each container only receives what it needs.
  ( umask 077
    grep -E '^(JWT_SECRET|INITIAL_PASSWORD|DATA_DIR|PORT|NODE_ENV|API_KEY_SECRET|MACHINE_ID_SALT|BASE_URL|NEXT_PUBLIC_BASE_URL)=' .env > data/9router.env || true
    grep -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_ALLOWED_USERS|HERMES_DASHBOARD[A-Z_]*|HERMES_UID|HERMES_GID)=' .env > data/hermes.env || true
    touch data/9router.env data/hermes.env )
  chmod 600 data/9router.env data/hermes.env
}

render_hermes_config() {
  local out=data/hermes/config.yaml.tmp
  sed \
    -e "s|__HERMES_MODEL_TARGET__|${HERMES_MODEL_TARGET:-}|g" \
    -e "s|__NINE_ROUTER_API_KEY__|${NINE_ROUTER_API_KEY:-}|g" \
    config/hermes-config.yaml.template > "$out"
  if [ "${HERMES_MODE:-lite}" = "full" ]; then
    # Strip the agent:/disabled_toolsets: block for full mode.
    awk '/^agent:/{skip=1} /^# Unattended/{skip=0} !skip' "$out" > data/hermes/config.yaml
    rm -f "$out"
  else
    mv "$out" data/hermes/config.yaml
  fi
  chmod 600 data/hermes/config.yaml   # contains the 9router API key
}

write_service_env_files
render_hermes_config
echo "  Wrote data/hermes/config.yaml (mode: ${HERMES_MODE:-lite})"

if [ "$WITH_PROXY" = "1" ]; then
  sed "s|__DOMAIN__|${PROXY_DOMAIN}|g" config/Caddyfile.template > config/Caddyfile
  echo "  Wrote config/Caddyfile for domain: $PROXY_DOMAIN"
fi

# -----------------------------------------------------------------------------
# Phase 6 — Bring services up
# -----------------------------------------------------------------------------
echo
echo "[6/9] Starting services ($CONTAINER_RUNTIME compose up -d)"
compose up -d

# -----------------------------------------------------------------------------
# Phase 7 — Combo auto-setup
# -----------------------------------------------------------------------------
echo
echo "[7/9] 9Router combo setup"
# The first render (above, before 9router/combo existed) wrote an empty
# model.default — always re-render once the real target is known.
if run_combo_setup; then
  echo "  Re-rendering Hermes config (model: ${HERMES_MODEL_TARGET}) and restarting hermes..."
  render_hermes_config
  compose restart hermes
else
  echo "  (continuing — connect a provider in the 9router dashboard and set"
  echo "   NINE_ROUTER_MODELS in .env, or run 'hermes model' inside the hermes"
  echo "   container to configure it directly, then re-run ./install.sh)"
fi

# -----------------------------------------------------------------------------
# Phase 8 — Health check + summary
# -----------------------------------------------------------------------------
echo
echo "[8/9] Health check"
run_post_install_healthcheck || true

# -----------------------------------------------------------------------------
# Phase 9 — Done
# -----------------------------------------------------------------------------
echo
echo "[9/9] Done."
