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

# 1. Test provider creation dry run with providerSpecificData (Cloudflare AI pattern)
prov_output="$(combo_create_provider "cloudflare" "cloudflare-ai" "cf-test-token" "{\"accountId\": \"cf-test-account-123\"}")"
if ! echo "${prov_output}" | grep -q '"provider": "cloudflare-ai"' || \
   ! echo "${prov_output}" | grep -q '"accountId": "cf-test-account-123"'; then
    echo "FAIL: Provider payload missing provider ID or accountId: ${prov_output}" >&2
    exit 1
fi
echo "  [PASS] Provider registration payload (provider field & providerSpecificData) verified"

# 2. Test fallback combo creation dry run with flat string array models
combo_output="$(combo_create_fallback_combo "combo-test" "nvidia/deepseek-ai/deepseek-v4-flash" "cloudflare-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast")"
if ! echo "${combo_output}" | grep -q '"models": \["nvidia/deepseek-ai/deepseek-v4-flash"' || \
   ! echo "${combo_output}" | grep -q 'cloudflare-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast'; then
    echo "FAIL: Combo payload does not match flat string array model format: ${combo_output}" >&2
    exit 1
fi
echo "  [PASS] Combo registration payload matches 9Router flat string array schema"

# 3. Test autoconfig from dummy .env file
TMP_ENV="/tmp/test_combo_env_$$"
cat > "${TMP_ENV}" <<EOF
NVIDIA_NIM_API_KEY=nv-sample-123
CLOUDFLARE_API_TOKEN=cf-sample-456
CLOUDFLARE_ACCOUNT_ID=cf-acc-789
BYTEPLUS_API_KEY=bp-sample-012
COMBO_NAME=my-test-combo
EOF

autoconfig_output="$(combo_run_autoconfig "${TMP_ENV}")"
rm -f "${TMP_ENV}"

if ! echo "${autoconfig_output}" | grep -q "my-test-combo"; then
    echo "FAIL: Autoconfig did not use configured combo name" >&2
    exit 1
fi
if ! echo "${autoconfig_output}" | grep -q "nvidia/deepseek-ai/deepseek-v4-flash"; then
    echo "FAIL: Autoconfig missing nvidia model tier" >&2
    exit 1
fi
if ! echo "${autoconfig_output}" | grep -q "cloudflare-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast"; then
    echo "FAIL: Autoconfig missing cloudflare model tier" >&2
    exit 1
fi
echo "  [PASS] Autoconfig parsed and registered NVIDIA, Cloudflare, and BytePlus tiers"

# 4. Test healthcheck dry run
hc_output="$(run_full_healthcheck "podman")"
if ! echo "${hc_output}" | grep -q "All health checks passed successfully"; then
    echo "FAIL: Healthcheck dry run failed" >&2
    exit 1
fi
echo "  [PASS] Healthcheck diagnostics verified"

echo "All Phase 5 combo and healthcheck tests passed successfully."
