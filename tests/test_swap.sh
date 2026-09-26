#!/usr/bin/env bash
# tests/test_swap.sh: Verification tests for lib/swap.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Testing lib/swap.sh functions..."

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/swap.sh"

# 1. Test swap size recommendations
size_512="$(calculate_recommended_swap_size 512)"
size_1024="$(calculate_recommended_swap_size 1024)"
size_2048="$(calculate_recommended_swap_size 2048)"
size_4096="$(calculate_recommended_swap_size 4096)"
size_8192="$(calculate_recommended_swap_size 8192)"

if [[ "${size_512}" -ne 2048 || "${size_1024}" -ne 2048 || "${size_2048}" -ne 2048 ]]; then
    echo "FAIL: Swap size recommendation incorrect for <= 2048MB: 512=${size_512}, 1024=${size_1024}, 2048=${size_2048}" >&2
    exit 1
fi

if [[ "${size_4096}" -ne 1024 || "${size_8192}" -ne 0 ]]; then
    echo "FAIL: Swap size recommendation incorrect for > 2048MB: 4096=${size_4096}, 8192=${size_8192}" >&2
    exit 1
fi
echo "  [PASS] Swap size calculation accurately handles RAM tiers"

# 2. Test should_configure_swap decisions
# Test --no-swap flag rejection
if should_configure_swap 1024 "true"; then
    echo "FAIL: should_configure_swap did not respect --no-swap flag" >&2
    exit 1
fi
echo "  [PASS] should_configure_swap respects --no-swap flag"

# Test high-RAM threshold bypass
if should_configure_swap 4096 "false"; then
    echo "FAIL: should_configure_swap did not bypass when RAM > threshold" >&2
    exit 1
fi
echo "  [PASS] should_configure_swap bypasses when RAM exceeds 2GB"

# 3. Test dry-run setup
SWAP_DRY_RUN=true
SWAP_FILE_PATH="/tmp/mock_swapfile_$$"

# Mock get_active_swap_mb to return 0 for low RAM scenario
get_active_swap_mb() {
    echo 0
}

setup_output="$(swap_setup 1024 false)"
if ! echo "${setup_output}" | grep -q "DRY-RUN"; then
    echo "FAIL: Dry-run output missing in swap_setup" >&2
    exit 1
fi
echo "  [PASS] Dry run swap allocation succeeded with proper output"

remove_output="$(swap_remove)"
if ! echo "${remove_output}" | grep -q "DRY-RUN"; then
    echo "FAIL: Dry-run output missing in swap_remove" >&2
    exit 1
fi
echo "  [PASS] Dry run swap deallocation succeeded"

# Unset mock
unset -f get_active_swap_mb

echo "All swap management tests passed successfully."
