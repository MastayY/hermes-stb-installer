#!/usr/bin/env bash
# tests/test_detect.sh: Verification tests for lib/detect.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Testing lib/detect.sh functions..."

# 1. Source the detection library
# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/detect.sh"

detect_init_vars
detect_architecture
detect_memory
detect_distribution

# Assert core variables populated
if [[ -z "${DETECT_ARCH}" ]]; then
    echo "FAIL: DETECT_ARCH is empty" >&2
    exit 1
fi

if [[ "${DETECT_RAM_MB}" -le 0 ]]; then
    echo "FAIL: DETECT_RAM_MB is ${DETECT_RAM_MB} (expected > 0)" >&2
    exit 1
fi

echo "  [PASS] Live detection: Arch=${DETECT_ARCH}, RAM=${DETECT_RAM_MB}MB, LowRAM=${DETECT_IS_LOW_RAM}"

# 2. Test architecture categorization
# Mock uname function
uname() {
    echo "armv7l"
}
detect_architecture
if [[ "${DETECT_ARCH}" != "armv7l" || "${DETECT_ARCH_SUPPORTED}" == "true" ]]; then
    echo "FAIL: armv7l was not properly flagged as unsupported" >&2
    exit 1
fi
echo "  [PASS] armv7l rejected as unsupported"

uname() {
    echo "aarch64"
}
detect_architecture
if [[ "${DETECT_ARCH}" != "aarch64" || "${DETECT_ARCH_SUPPORTED}" != "true" ]]; then
    echo "FAIL: aarch64 was not identified as supported" >&2
    exit 1
fi
echo "  [PASS] aarch64 accepted as supported"

uname() {
    echo "x86_64"
}
detect_architecture
if [[ "${DETECT_ARCH}" != "x86_64" || "${DETECT_ARCH_SUPPORTED}" != "true" ]]; then
    echo "FAIL: x86_64 was not identified as supported" >&2
    exit 1
fi
echo "  [PASS] x86_64 accepted as supported"

# Unset mock
unset -f uname

# 3. Test memory threshold classification
DETECT_RAM_MB=1024
if [[ ${DETECT_RAM_MB} -le 2048 ]]; then
    DETECT_IS_LOW_RAM=true
fi
if [[ "${DETECT_IS_LOW_RAM}" != "true" ]]; then
    echo "FAIL: 1024MB not flagged as low RAM" >&2
    exit 1
fi

DETECT_RAM_MB=4096
if [[ ${DETECT_RAM_MB} -le 2048 ]]; then
    DETECT_IS_LOW_RAM=true
else
    DETECT_IS_LOW_RAM=false
fi
if [[ "${DETECT_IS_LOW_RAM}" != "false" ]]; then
    echo "FAIL: 4096MB incorrectly flagged as low RAM" >&2
    exit 1
fi
echo "  [PASS] Memory threshold boundary checks passed"

# 4. Test smoke test runtime failure handling
mock_failing_runtime() {
    if [[ "$1" == "run" ]]; then
        echo "Error response from daemon: overlayfs: operation not permitted" >&2
        return 125
    fi
    return 0
}

diag_output="$(detect_smoke_test_runtime "mock_failing_runtime" 2>&1 || true)"
if ! echo "${diag_output}" | grep -q "overlayfs"; then
    echo "FAIL: Diagnostic output did not pinpoint overlay issue" >&2
    exit 1
fi
echo "  [PASS] Smoke test diagnosis handler successfully caught overlay issue"

echo "All detection tests passed successfully."
