#!/usr/bin/env bash
# tests/test_install.sh: End-to-end verification test for install.sh in dry-run mode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Testing Phase 8 Main installer entrypoint (install.sh)..."

# 1. Test help flag
"${REPO_ROOT}/install.sh" --help >/dev/null
echo "  [PASS] install.sh --help flag verified"

# 2. Test full installer run in dry-run mode with Podman + Lite mode
export RUNTIME_DRY_RUN=true
export PODMAN_SETUP_DRY_RUN=true
export DOCKER_FIX_DRY_RUN=true
export SWAP_DRY_RUN=true
export COMBO_SETUP_DRY_RUN=true
export HEALTHCHECK_DRY_RUN=true
export DOCKER_FIX_SKIP_RELOAD=true

install_podman_output="$("${REPO_ROOT}/install.sh" --lite --runtime=podman --no-swap --non-interactive 2>&1)"

if ! echo "${install_podman_output}" | grep -q "Installation Successfully Completed"; then
    echo "FAIL: install.sh (podman) did not report successful completion" >&2
    echo "${install_podman_output}" >&2
    exit 1
fi

if ! echo "${install_podman_output}" | grep -q "Active Runtime      : podman"; then
    echo "FAIL: install.sh did not identify podman as active runtime" >&2
    exit 1
fi

if ! echo "${install_podman_output}" | grep -q "Lite (RAM-optimized)"; then
    echo "FAIL: install.sh did not identify lite profile" >&2
    exit 1
fi
echo "  [PASS] install.sh (podman + lite) end-to-end dry run successful"

# 3. Test full installer run in dry-run mode with Docker + Proxy
install_docker_output="$("${REPO_ROOT}/install.sh" --runtime=docker --with-proxy --no-swap --non-interactive 2>&1)"

if ! echo "${install_docker_output}" | grep -q "Installation Successfully Completed"; then
    echo "FAIL: install.sh (docker + proxy) did not report successful completion" >&2
    echo "${install_docker_output}" >&2
    exit 1
fi

if ! echo "${install_docker_output}" | grep -q "Active Runtime      : docker"; then
    echo "FAIL: install.sh did not identify docker as active runtime" >&2
    exit 1
fi

if ! echo "${install_docker_output}" | grep -q "Reverse Proxy       : Enabled (Caddy TLS)"; then
    echo "FAIL: install.sh did not identify reverse proxy enablement" >&2
    exit 1
fi
echo "  [PASS] install.sh (docker + proxy) end-to-end dry run successful"

echo "All Phase 8 installer tests passed successfully."
