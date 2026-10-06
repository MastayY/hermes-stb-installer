#!/usr/bin/env bash
# tests/smoke-test.sh — run after install.sh to verify the basics.
# Exit code 0 = all checks passed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1

pass=0
fail=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    pass=$((pass + 1))
  else
    echo "  FAIL: $desc"
    fail=$((fail + 1))
  fi
}

echo "hermes-9router-stb-installer — smoke test"
echo

if [ -f .env ]; then
  set -a; . ./.env; set +a
fi
BASE="${BASE_URL:-http://localhost:20128}"

# SKIP_CONTAINER_CHECKS=1 lets the HTTP checks run against a 9router started
# some other way (e.g. from source during development).
if [ "${SKIP_CONTAINER_CHECKS:-0}" != "1" ]; then
  if [ -f .runtime ]; then
    RUNTIME="$(cat .runtime)"
  else
    echo "  FAIL: .runtime not found — was install.sh run?"
    exit 1
  fi
  check "9router container is running" \
    bash -c "$RUNTIME ps --filter name=9router --filter status=running --format '{{.Names}}' | grep -q 9router"
  check "hermes container is running" \
    bash -c "$RUNTIME ps --filter name=hermes --filter status=running --format '{{.Names}}' | grep -q hermes"
  check "data/hermes/config.yaml exists" test -f data/hermes/config.yaml
  check "data/9router directory is non-empty (DB initialized)" \
    bash -c "[ -n \"\$(ls -A data/9router 2>/dev/null)\" ]"
fi

# --- HTTP checks (each one was validated against a live 9router instance) ---
check "9router /api/health returns ok:true" \
  bash -c "curl -fsS $BASE/api/health | grep -q '\"ok\":true'"

check "dashboard is reachable (redirects to /login when logged out)" \
  bash -c "c=\$(curl -s -o /dev/null -w '%{http_code}' $BASE/dashboard); [ \"\$c\" = 307 ] || [ \"\$c\" = 200 ]"

check "admin API is protected (POST /api/providers without login -> 401)" \
  bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' -X POST $BASE/api/providers -H 'Content-Type: application/json' -d '{}')\" = 401 ]"

if [ -n "${NINE_ROUTER_API_KEY:-}" ]; then
  # The exact contract Hermes uses: OpenAI-compatible /v1 with a Bearer key.
  # Any status except 401/404 proves auth + combo resolution work; upstream
  # provider errors (5xx) are fine here, we are not testing the providers.
  check "Hermes->9router contract: /v1/chat/completions with API key passes auth and finds the combo" \
    bash -c "c=\$(curl -s -o /dev/null -w '%{http_code}' -m 90 -X POST $BASE/v1/chat/completions -H 'Authorization: Bearer $NINE_ROUTER_API_KEY' -H 'Content-Type: application/json' -d '{\"model\":\"${NINE_ROUTER_COMBO_NAME:-stb-default}\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}'); [ \"\$c\" != 401 ] && [ \"\$c\" != 404 ] && [ \"\$c\" != 000 ]"
  check "combo is listed in /v1/models" \
    bash -c "curl -fsS -H 'Authorization: Bearer $NINE_ROUTER_API_KEY' $BASE/v1/models | grep -q '\"id\":\"${NINE_ROUTER_COMBO_NAME:-stb-default}\"'"
else
  echo "  SKIP: NINE_ROUTER_API_KEY not in .env — Hermes->9router contract checks not run"
fi

check "a wrong API key is rejected (401)" \
  bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' -X POST $BASE/v1/chat/completions -H 'Authorization: Bearer sk-wrong' -H 'Content-Type: application/json' -d '{\"model\":\"x\",\"messages\":[]}')\" = 401 ]"

echo
echo "Result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
