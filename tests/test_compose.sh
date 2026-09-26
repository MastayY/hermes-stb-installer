#!/usr/bin/env bash
# tests/test_compose.sh: Validation test for compose definitions and configuration templates.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Testing Phase 4 Compose definitions..."

COMPOSE_STD="${REPO_ROOT}/compose/docker-compose.yml"
COMPOSE_LITE="${REPO_ROOT}/compose/docker-compose.lite.yml"
HERMES_CONFIG="${REPO_ROOT}/config/hermes-config.template.yaml"
ENV_EXAMPLE="${REPO_ROOT}/.env.example"

# 1. Verify existence
for f in "${COMPOSE_STD}" "${COMPOSE_LITE}" "${HERMES_CONFIG}" "${ENV_EXAMPLE}"; do
    if [[ ! -f "${f}" ]]; then
        echo "FAIL: Required file missing: ${f}" >&2
        exit 1
    fi
done
echo "  [PASS] All Phase 4 required files exist"

# 2. Validate YAML syntax using Python
python3 -c "
import yaml

with open('${COMPOSE_STD}') as f:
    std = yaml.safe_load(f)
assert 'router' in std['services'], 'Missing router service in standard compose'
assert 'hermes' in std['services'], 'Missing hermes service in standard compose'
assert std['services']['router']['deploy']['resources']['limits']['memory'] == '384M'
assert std['services']['hermes']['deploy']['resources']['limits']['memory'] == '768M'
router_env = std['services']['router']['environment']
assert any('INITIAL_PASSWORD=' in e for e in router_env), 'Missing INITIAL_PASSWORD in router env'
assert any('REQUIRE_API_KEY=' in e for e in router_env), 'Missing REQUIRE_API_KEY in router env'

with open('${COMPOSE_LITE}') as f:
    lite = yaml.safe_load(f)
assert 'router' in lite['services'], 'Missing router service in lite compose'
assert 'hermes' in lite['services'], 'Missing hermes service in lite compose'
assert lite['services']['router']['deploy']['resources']['limits']['memory'] == '256M'
assert lite['services']['hermes']['deploy']['resources']['limits']['memory'] == '448M'

# Verify lite environment flags
env_vars = lite['services']['hermes']['environment']
assert any('BROWSER_BACKEND=off' in e for e in env_vars), 'Missing BROWSER_BACKEND=off in lite env'
assert any('HERMES_DISABLE_BROWSER=1' in e for e in env_vars), 'Missing HERMES_DISABLE_BROWSER=1 in lite env'

with open('${HERMES_CONFIG}') as f:
    cfg = yaml.safe_load(f)
assert cfg['browser']['backend'] == 'off', 'Hermes config template must disable browser'
assert cfg['model']['provider'] == 'custom', 'Hermes config template must point to custom router'

# Verify official agent.disabled_toolsets list
disabled = cfg['agent']['disabled_toolsets']
expected = ['browser', 'vision', 'image_gen', 'video_gen', 'tts', 'computer_use']
for toolset in expected:
    assert toolset in disabled, f'Missing {toolset} in agent.disabled_toolsets'
"
echo "  [PASS] Compose YAML structures, memory limits, and lite parameters successfully validated"

echo "All Phase 4 compose tests passed successfully."
