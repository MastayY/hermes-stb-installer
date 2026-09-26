#!/usr/bin/env bash
# lib/combo-setup.sh: Automatic provider and fallback combo registration for 9Router.

ROUTER_HOST="${ROUTER_HOST:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-20128}"
ROUTER_BASE_URL="http://${ROUTER_HOST}:${ROUTER_PORT}"

# Wait for 9Router service to become responsive
combo_wait_for_router() {
    local max_retries="${1:-30}"
    local delay="${2:-2}"
    local retries=0

    echo "Waiting for 9Router API at ${ROUTER_BASE_URL} to become ready..."

    if [[ "${COMBO_SETUP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] 9Router liveness check simulated successfully."
        return 0
    fi

    while [[ ${retries} -lt ${max_retries} ]]; do
        if curl -fsSL "${ROUTER_BASE_URL}/v1/models" >/dev/null 2>&1 || \
           curl -fsSL "${ROUTER_BASE_URL}/api/providers" >/dev/null 2>&1; then
            echo "9Router is ready and accepting requests."
            return 0
        fi
        retries=$((retries + 1))
        sleep "${delay}"
    done

    echo "WARNING: 9Router did not respond within $((max_retries * delay)) seconds." >&2
    return 1
}

# Register a single provider in 9Router
combo_create_provider() {
    local name="$1"
    local provider_id="$2"
    local api_key="$3"
    local provider_specific_data="${4:-}"
    local base_url="${5:-}"

    if [[ -z "${api_key}" ]]; then
        return 0
    fi

    echo "Configuring provider '${name}' (${provider_id}) in 9Router..."

    local payload
    payload="$(python3 -c "
import json
data = {
    'provider': '${provider_id}',
    'name': '${name}',
    'apiKey': '${api_key}',
    'enabled': True
}
specific_raw = '''${provider_specific_data}'''.strip()
if specific_raw:
    try:
        data['providerSpecificData'] = json.loads(specific_raw)
    except Exception:
        pass
if '${base_url}':
    data['baseUrl'] = '${base_url}'
print(json.dumps(data))
")"

    if [[ "${COMBO_SETUP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] POST ${ROUTER_BASE_URL}/api/providers with payload: ${payload}"
        return 0
    fi

    local response
    local status=0
    response="$(curl -s -w "\n%{http_code}" -X POST "${ROUTER_BASE_URL}/api/providers" \
        -H "Content-Type: application/json" \
        -d "${payload}" 2>&1)" || status=$?

    local http_code
    http_code="$(echo "${response}" | tail -n1)"
    local body
    body="$(echo "${response}" | sed '$d')"

    if [[ ${status} -ne 0 || ( "${http_code}" != "200" && "${http_code}" != "201" ) ]]; then
        echo "WARNING: Failed to configure provider '${name}' (HTTP ${http_code}): ${body}" >&2
        return 1
    fi

    echo "Provider '${name}' configured successfully."
    return 0
}

# Register fallback combo in 9Router (models is string[] formatted as '<alias>/<modelId>')
combo_create_fallback_combo() {
    local combo_name="${1:-combo-primary}"
    shift
    local models=("$@")

    if [[ ${#models[@]} -eq 0 ]]; then
        echo "No models configured for fallback combo '${combo_name}'."
        return 0
    fi

    echo "Registering fallback combo '${combo_name}' with ${#models[@]} model tiers..."

    local payload
    payload="$(python3 -c "
import json, sys
models = sys.argv[1:]
print(json.dumps({
    'name': '${combo_name}',
    'kind': 'fallback',
    'strategy': 'fallback',
    'models': models,
    'enabled': True
}))
" "${models[@]}")"

    if [[ "${COMBO_SETUP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] POST ${ROUTER_BASE_URL}/api/combos with payload: ${payload}"
        return 0
    fi

    local response
    local status=0
    response="$(curl -s -w "\n%{http_code}" -X POST "${ROUTER_BASE_URL}/api/combos" \
        -H "Content-Type: application/json" \
        -d "${payload}" 2>&1)" || status=$?

    local http_code
    http_code="$(echo "${response}" | tail -n1)"
    local body
    body="$(echo "${response}" | sed '$d')"

    if [[ ${status} -ne 0 || ( "${http_code}" != "200" && "${http_code}" != "201" ) ]]; then
        echo "WARNING: Failed to register combo '${combo_name}' (HTTP ${http_code}): ${body}" >&2
        return 1
    fi

    echo "Fallback combo '${combo_name}' successfully registered."
    return 0
}

# Parse env file and auto-configure all detected providers
combo_run_autoconfig() {
    local env_file="${1:-.env}"

    if [[ ! -f "${env_file}" ]]; then
        echo "Environment file '${env_file}' not found. Skipping combo auto-configuration."
        return 0
    fi

    # Load variables safely
    local openrouter_key=""
    local deepseek_key=""
    local groq_key=""
    local nvidia_key=""
    local byteplus_key=""
    local cf_token=""
    local cf_account_id=""
    local combo_name="combo-primary"

    # shellcheck disable=SC1090
    while IFS='=' read -r key val || [[ -n "${key}" ]]; do
        # Strip comments and whitespace
        key="$(echo "${key}" | tr -d '[:space:]')"
        val="$(echo "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
        case "${key}" in
            OPENROUTER_API_KEY)   openrouter_key="${val}" ;;
            DEEPSEEK_API_KEY)     deepseek_key="${val}" ;;
            GROQ_API_KEY)         groq_key="${val}" ;;
            NVIDIA_NIM_API_KEY)   nvidia_key="${val}" ;;
            BYTEPLUS_API_KEY)     byteplus_key="${val}" ;;
            CLOUDFLARE_API_TOKEN) cf_token="${val}" ;;
            CLOUDFLARE_ACCOUNT_ID) cf_account_id="${val}" ;;
            COMBO_NAME)           combo_name="${val}" ;;
        esac
    done < "${env_file}"

    local configured_models=()

    # Configure registered providers according to 9Router registry
    if [[ -n "${nvidia_key}" ]]; then
        combo_create_provider "nvidia" "nvidia" "${nvidia_key}"
        configured_models+=("nvidia/deepseek-ai/deepseek-v4-flash")
    fi

    if [[ -n "${openrouter_key}" ]]; then
        combo_create_provider "openrouter" "openrouter" "${openrouter_key}"
        configured_models+=("openrouter/anthropic/claude-3.5-haiku")
    fi

    if [[ -n "${deepseek_key}" ]]; then
        combo_create_provider "deepseek" "deepseek" "${deepseek_key}" "" "https://api.deepseek.com/v1"
        configured_models+=("deepseek/deepseek-chat")
    fi

    if [[ -n "${groq_key}" ]]; then
        combo_create_provider "groq" "groq" "${groq_key}" "" "https://api.groq.com/openai/v1"
        configured_models+=("groq/llama-3.3-70b-versatile")
    fi

    if [[ -n "${cf_token}" ]]; then
        local cf_data=""
        if [[ -n "${cf_account_id}" ]]; then
            cf_data="{\"accountId\": \"${cf_account_id}\"}"
        fi
        combo_create_provider "cloudflare" "cloudflare-ai" "${cf_token}" "${cf_data}"
        configured_models+=("cloudflare-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast")
    fi

    if [[ -n "${byteplus_key}" ]]; then
        combo_create_provider "byteplus" "byteplus" "${byteplus_key}"
        configured_models+=("byteplus/doubao-pro-32k")
    fi

    if [[ ${#configured_models[@]} -gt 0 ]]; then
        combo_create_fallback_combo "${combo_name}" "${configured_models[@]}"
    else
        echo "Note: No provider API keys were set in ${env_file}."
        echo "You can configure providers later via the 9Router web dashboard."
    fi

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    target_env="${1:-.env}"
    combo_run_autoconfig "${target_env}"
fi
