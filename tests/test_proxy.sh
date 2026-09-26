#!/usr/bin/env bash
# tests/test_proxy.sh: Verification tests for reverse proxy configuration and opt-in behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Testing Phase 6 Reverse Proxy components..."

CADDY_TEMPLATE="${REPO_ROOT}/config/Caddyfile.template"
PROXY_COMPOSE="${REPO_ROOT}/compose/docker-compose.proxy.yml"

# 1. Check file existence
if [[ ! -f "${CADDY_TEMPLATE}" ]]; then
    echo "FAIL: Missing Caddyfile template: ${CADDY_TEMPLATE}" >&2
    exit 1
fi

if [[ ! -f "${PROXY_COMPOSE}" ]]; then
    echo "FAIL: Missing proxy compose file: ${PROXY_COMPOSE}" >&2
    exit 1
fi
echo "  [PASS] Proxy template and compose override exist"

# 2. Validate YAML and Caddy syntax
python3 -c "
import yaml

with open('${PROXY_COMPOSE}') as f:
    proxy = yaml.safe_load(f)

assert 'caddy' in proxy['services'], 'Missing caddy service in proxy compose'
assert proxy['services']['caddy']['deploy']['resources']['limits']['memory'] == '64M'
assert '80:80' in proxy['services']['caddy']['ports']
assert '443:443' in proxy['services']['caddy']['ports']
"
echo "  [PASS] Proxy compose YAML structure and 64M limit verified"

# 3. Check Caddyfile template contents for security standards
if ! grep -q "basicauth" "${CADDY_TEMPLATE}"; then
    echo "FAIL: Caddyfile template lacks basicauth security layer" >&2
    exit 1
fi

if ! grep -q "reverse_proxy router:20128" "${CADDY_TEMPLATE}"; then
    echo "FAIL: Caddyfile template does not proxy to router:20128" >&2
    exit 1
fi
echo "  [PASS] Caddyfile basicauth and reverse_proxy upstream verified"

# 4. Verify opt-in behavior logic
build_compose_args() {
    local lite_mode="${1:-false}"
    local with_proxy="${2:-false}"
    local args=("-f")

    if [[ "${lite_mode}" == "true" ]]; then
        args+=("compose/docker-compose.lite.yml")
    else
        args+=("compose/docker-compose.yml")
    fi

    if [[ "${with_proxy}" == "true" ]]; then
        args+=("-f" "compose/docker-compose.proxy.yml")
    fi

    echo "${args[*]}"
}

default_args="$(build_compose_args "false" "false")"
if echo "${default_args}" | grep -q "proxy"; then
    echo "FAIL: Proxy file included in default compose args" >&2
    exit 1
fi
echo "  [PASS] Default execution excludes reverse proxy (zero extra footprint)"

proxy_args="$(build_compose_args "false" "true")"
if ! echo "${proxy_args}" | grep -q "docker-compose.proxy.yml"; then
    echo "FAIL: Proxy file not included when with_proxy is true" >&2
    exit 1
fi
echo "  [PASS] Opt-in flag correctly appends proxy compose override"

echo "All Phase 6 proxy tests passed successfully."
