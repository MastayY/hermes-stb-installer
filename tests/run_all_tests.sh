#!/usr/bin/env bash
# tests/run_all_tests.sh: Master test suite running all verification and smoke tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=========================================================="
echo "    Hermes + 9Router Installer Master Test Suite          "
echo "=========================================================="

FAILED_TESTS=()
PASSED_COUNT=0

# 1. Syntax Check on all shell scripts
echo "[Step 1] Checking Bash syntax on all repository scripts..."
while IFS= read -r script_file; do
    if ! bash -n "${script_file}"; then
        echo "SYNTAX ERROR: ${script_file}" >&2
        FAILED_TESTS+=("Syntax:${script_file}")
    fi
done < <(find "${REPO_ROOT}" -maxdepth 3 -name "*.sh" -not -path "*/.git/*")
echo "  [PASS] All shell scripts passed syntax checks"

# 2. Run Individual Test Suites
TEST_SCRIPTS=(
    "test_detect.sh"
    "test_swap.sh"
    "test_runtime.sh"
    "test_compose.sh"
    "test_combo.sh"
    "test_proxy.sh"
    "test_lifecycle.sh"
    "test_install.sh"
)

echo "[Step 2] Executing module test suites..."
for t in "${TEST_SCRIPTS[@]}"; do
    test_path="${SCRIPT_DIR}/${t}"
    echo "----------------------------------------------------------"
    echo "Running ${t}..."
    if bash "${test_path}"; then
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo "FAILED: ${t}" >&2
        FAILED_TESTS+=("${t}")
    fi
done

echo "=========================================================="
echo "                  Test Suite Summary                      "
echo "=========================================================="
echo "Passed: ${PASSED_COUNT} / ${#TEST_SCRIPTS[@]}"

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    echo "The following tests failed:" >&2
    for f in "${FAILED_TESTS[@]}"; do
        echo "  - ${f}" >&2
    done
    exit 1
else
    echo "ALL TESTS PASSED WITH ZERO ERRORS."
    exit 0
fi
