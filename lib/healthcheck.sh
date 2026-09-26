#!/usr/bin/env bash
# lib/healthcheck.sh: Post-installation health verification and memory usage diagnostics.

ROUTER_HOST="${ROUTER_HOST:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-20128}"

healthcheck_router_endpoint() {
    local endpoint_url="http://${ROUTER_HOST}:${ROUTER_PORT}/v1/models"
    echo "Checking 9Router API endpoint (${endpoint_url})..."

    if [[ "${HEALTHCHECK_DRY_RUN:-false}" == "true" ]]; then
        echo "  [PASS] 9Router endpoint responding (simulated)."
        return 0
    fi

    if curl -fsSL "${endpoint_url}" >/dev/null 2>&1; then
        echo "  [PASS] 9Router API is responding correctly."
        return 0
    else
        echo "  [FAIL] 9Router API at ${endpoint_url} is not responding." >&2
        return 1
    fi
}

healthcheck_containers() {
    local runtime="${1:-podman}"
    echo "Checking container statuses with runtime '${runtime}'..."

    if [[ "${HEALTHCHECK_DRY_RUN:-false}" == "true" ]]; then
        echo "  [PASS] 9router container: Up (simulated)"
        echo "  [PASS] hermes-agent container: Up (simulated)"
        return 0
    fi

    if ! command -v "${runtime}" >/dev/null 2>&1; then
        echo "  [FAIL] Runtime '${runtime}' not found in PATH." >&2
        return 1
    fi

    local ps_output
    ps_output="$("${runtime}" ps --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)"

    local router_ok=false
    local hermes_ok=false

    if echo "${ps_output}" | grep -q "9router"; then
        router_ok=true
        echo "  [PASS] 9router container is active."
    else
        echo "  [FAIL] 9router container is not running." >&2
    fi

    if echo "${ps_output}" | grep -q "hermes"; then
        hermes_ok=true
        echo "  [PASS] hermes-agent container is active."
    else
        echo "  [FAIL] hermes-agent container is not running." >&2
    fi

    if [[ "${router_ok}" == "true" && "${hermes_ok}" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

healthcheck_memory_usage() {
    local runtime="${1:-podman}"
    echo "Measuring actual container memory consumption..."

    if [[ "${HEALTHCHECK_DRY_RUN:-false}" == "true" ]]; then
        echo "  - 9router      : ~82 MB RSS"
        echo "  - hermes-agent : ~194 MB RSS"
        echo "  - Total stack  : ~276 MB RSS"
        return 0
    fi

    if ! command -v "${runtime}" >/dev/null 2>&1; then
        return 0
    fi

    local stats_output
    stats_output="$("${runtime}" stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || true)"

    if [[ -n "${stats_output}" ]]; then
        echo "${stats_output}"
    else
        echo "Memory stats currently unavailable."
    fi

    return 0
}

run_full_healthcheck() {
    local runtime="${1:-podman}"

    echo "=========================================================="
    echo "           Post-Installation Health Diagnostics           "
    echo "=========================================================="
    local status=0
    healthcheck_containers "${runtime}" || status=1
    healthcheck_router_endpoint || status=1
    healthcheck_memory_usage "${runtime}" || true
    echo "=========================================================="

    if [[ ${status} -eq 0 ]]; then
        echo "All health checks passed successfully."
        return 0
    else
        echo "Some health checks reported errors. Review logs above." >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_full_healthcheck "${1:-podman}"
fi
