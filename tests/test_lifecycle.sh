#!/usr/bin/env bash
# tests/test_lifecycle.sh: Verification tests for uninstall.sh and update.sh lifecycle scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Testing Phase 7 Lifecycle scripts (uninstall.sh & update.sh)..."

# 1. Verify help flags
"${REPO_ROOT}/uninstall.sh" --help >/dev/null
"${REPO_ROOT}/update.sh" --help >/dev/null
echo "  [PASS] CLI help flags verified"

# 2. Test uninstall dry run
export RUNTIME_DRY_RUN=true
export PODMAN_SETUP_DRY_RUN=true
export DOCKER_FIX_DRY_RUN=true
export SWAP_DRY_RUN=true

uninstall_output="$("${REPO_ROOT}/uninstall.sh" --force --remove-swap 2>&1)"
if ! echo "${uninstall_output}" | grep -q "Uninstall completed cleanly"; then
    echo "FAIL: uninstall.sh dry run did not report clean completion" >&2
    echo "${uninstall_output}" >&2
    exit 1
fi
echo "  [PASS] uninstall.sh dry run executed cleanly"

# 3. Test update dry run
export HEALTHCHECK_DRY_RUN=true

update_output="$("${REPO_ROOT}/update.sh" --lite --with-proxy 2>&1)"
if ! echo "${update_output}" | grep -q "Update completed successfully"; then
    echo "FAIL: update.sh dry run did not report successful completion" >&2
    echo "${update_output}" >&2
    exit 1
fi
echo "  [PASS] update.sh dry run executed cleanly"

echo "All Phase 7 lifecycle tests passed successfully."
