#!/usr/bin/env bash
# tests/test_runtime.sh: Verification tests for runtime selection, podman setup, and docker fixes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Testing Phase 3 runtime components..."

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/runtime-select.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/podman-setup.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/docker-fix.sh"

# Enable dry-run modes for isolated test environment
RUNTIME_DRY_RUN=true
PODMAN_SETUP_DRY_RUN=true
DOCKER_FIX_DRY_RUN=true
DOCKER_FIX_SKIP_RELOAD=true

# 1. Test runtime-select logic
res_default="$(runtime_determine "")"
if [[ "${res_default}" != "podman" ]]; then
    echo "FAIL: Default runtime is not podman (${res_default})" >&2
    exit 1
fi

res_docker="$(runtime_determine "docker")"
if [[ "${res_docker}" != "docker" ]]; then
    echo "FAIL: Explicit docker runtime was not returned" >&2
    exit 1
fi

res_podman="$(runtime_determine "podman")"
if [[ "${res_podman}" != "podman" ]]; then
    echo "FAIL: Explicit podman runtime was not returned" >&2
    exit 1
fi

if runtime_determine "unsupported_runtime" 2>/dev/null; then
    echo "FAIL: Invalid runtime name did not produce an error" >&2
    exit 1
fi
echo "  [PASS] Runtime determination logic verified"

# Test state save and load
TMP_STATE="/tmp/test_runtime_state_$$"
RUNTIME_DRY_RUN=false
runtime_save_state "docker" "${TMP_STATE}"
loaded_state="$(runtime_load_state "${TMP_STATE}")"
rm -f "${TMP_STATE}"
RUNTIME_DRY_RUN=true

if [[ "${loaded_state}" != "docker" ]]; then
    echo "FAIL: Saved runtime state '${loaded_state}' != 'docker'" >&2
    exit 1
fi
echo "  [PASS] Runtime state save and load verified"

# 2. Test podman-setup dry runs
podman_enable_user_linger "testuser"
podman_verify_subuid_subgid "testuser"
podman_setup_systemd_service "/tmp/install_dir" "compose/docker-compose.yml"
podman_remove_systemd_service
echo "  [PASS] Podman rootless setup functions verified"

# 3. Test docker daemon.json creation & merge
TMP_DAEMON_JSON="/tmp/test_daemon_$$.json"
DOCKER_FIX_DRY_RUN=false
DOCKER_DAEMON_JSON="${TMP_DAEMON_JSON}"

# Run 1: Create fresh file
docker_apply_daemon_json
if ! grep -q "max-size" "${TMP_DAEMON_JSON}"; then
    echo "FAIL: Fresh daemon.json missing max-size" >&2
    rm -f "${TMP_DAEMON_JSON}"
    exit 1
fi

# Run 2: Idempotency merge with existing user key
python3 -c "
import json
with open('${TMP_DAEMON_JSON}', 'r') as f:
    data = json.load(f)
data['custom-key'] = 'keep-me'
with open('${TMP_DAEMON_JSON}', 'w') as f:
    json.dump(data, f)
"
docker_apply_daemon_json

if ! grep -q "custom-key" "${TMP_DAEMON_JSON}" || ! grep -q "10m" "${TMP_DAEMON_JSON}"; then
    echo "FAIL: Existing key was wiped during daemon.json merge" >&2
    rm -f "${TMP_DAEMON_JSON}"
    exit 1
fi
rm -f "${TMP_DAEMON_JSON}"
echo "  [PASS] Docker daemon.json configuration & idempotency verified"

# 4. Test docker UFW rule insertion, idempotency, and revert
TMP_UFW_RULES="/tmp/test_after_$$.rules"
cat > "${TMP_UFW_RULES}" <<EOF
# Sample after.rules
*filter
:ufw-after-input - [0:0]
COMMIT
EOF

UFW_AFTER_RULES="${TMP_UFW_RULES}"

# Run 1: Apply rules
docker_apply_ufw_rules

if ! grep -q "BEGIN HERMES STB UFW DOCKER USER" "${TMP_UFW_RULES}"; then
    echo "FAIL: UFW rules not found in test rules file" >&2
    rm -f "${TMP_UFW_RULES}"
    exit 1
fi

# Run 2: Apply rules again (must be idempotent without duplicating)
docker_apply_ufw_rules
count_markers="$(grep -c "BEGIN HERMES STB UFW DOCKER USER" "${TMP_UFW_RULES}")"
if [[ "${count_markers}" -ne 1 ]]; then
    echo "FAIL: Duplicate UFW rules inserted on second run (count=${count_markers})" >&2
    rm -f "${TMP_UFW_RULES}"
    exit 1
fi
echo "  [PASS] UFW rules insertion and idempotency verified"

# Run 3: Revert rules
docker_revert_ufw_rules
if grep -q "BEGIN HERMES STB UFW DOCKER USER" "${TMP_UFW_RULES}"; then
    echo "FAIL: UFW rules were not cleanly removed on revert" >&2
    rm -f "${TMP_UFW_RULES}"
    exit 1
fi
rm -f "${TMP_UFW_RULES}"
echo "  [PASS] UFW rules clean revert verified"

echo "All Phase 3 runtime tests passed successfully."
