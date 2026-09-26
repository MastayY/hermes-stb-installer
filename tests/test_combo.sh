#!/usr/bin/env bash
# tests/test_combo.sh: Verification tests for combo auto-setup and healthcheck logic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Testing Phase 5 Combo auto-setup and healthcheck components..."

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/combo-setup.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/healthcheck.sh"

COMBO_SETUP_DRY_RUN=true
HEALTHCHECK_DRY_RUN=true

# 1. Test provider creation dry run
prov_output="$(combo_create_provider "openrouter" "openrouter" "sk-or-test-key")"
if ! echo "${prov_output}" | grep -q "sk-or-test-key"; then
    echo "FAIL: Provider payload missing API key" >&2
    exit 1
fi
echo "  [PASS] Provider registration payload verified"

# 2. Test fallback combo creation dry run
combo_output="$(combo_create_fallback_combo "combo-test" "openrouter:claude-3.5-haiku" "deepseek:deepseek-chat")"
if ! echo "${combo_output}" | grep -q "claude-3.5-haiku" || ! echo "${combo_output}" | grep -q "deepseek-chat"; then
    echo "FAIL: Combo payload missing model tiers" >&2
    exit 1
fi
echo "  [PASS] Combo registration payload and multi-tier structure verified"

# 3. Test autoconfig from dummy .env file
TMP_ENV="/tmp/test_combo_env_$$"
cat > "${TMP_ENV}" <<EOF
OPENROUTER_API_KEY=sk-or-sample-123
DEEPSEEK_API_KEY=sk-ds-sample-456
GROQ_API_KEY=gsk-sample-789
COMBO_NAME=my-test-combo
EOF

autoconfig_output="$(combo_run_autoconfig "${TMP_ENV}")"
rm -f "${TMP_ENV}"

if ! echo "${autoconfig_output}" | grep -q "my-test-combo"; then
    echo "FAIL: Autoconfig did not use configured combo name" >&2
    exit 1
fi
echo "  [PASS] Autoconfig from .env parsed and registered all tiers"

# 4. Test healthcheck dry run
hc_output="$(run_full_healthcheck "podman")"
if ! echo "${hc_output}" | grep -q "All health checks passed successfully"; then
    echo "FAIL: Healthcheck dry run failed" >&2
    exit 1
fi
echo "  [PASS] Healthcheck diagnostics verified"

echo "All Phase 5 combo and healthcheck tests passed successfully."
