#!/usr/bin/env bash
NINE_ROUTER_URL="${BASE_URL:-http://localhost:20128}"
COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  combo-setup: jq not found, installing..."
    # A failing third-party apt source must not block installing jq (found by
    # testing: a blocked repo made `apt-get update && install` skip the
    # install entirely), so the update step is best-effort.
    apt-get update -qq || echo "  combo-setup: apt-get update reported errors, trying install anyway" >&2
    apt-get install -y jq || true
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for combo setup and could not be installed." >&2
    echo "       Install it manually (apt-get install jq) and re-run." >&2
    return 1
  fi
}

wait_for_9router() {
  local retries=30
  echo "  combo-setup: waiting for 9router at $NINE_ROUTER_URL ..."
  until curl -fsS "$NINE_ROUTER_URL/api/health" >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "ERROR: 9router did not become healthy in time." >&2
      return 1
    fi
    sleep 2
  done
  echo "  combo-setup: 9router is healthy"
}

# One login attempt only: 9router locks out after 5 wrong passwords.
_nine_router_login() {
  local body code
  body="$(jq -n --arg p "${INITIAL_PASSWORD:-123456}" '{password:$p}')"
  code="$(curl -sS -o /dev/null -w '%{http_code}' -c "$COOKIE_JAR" -X POST \
    "$NINE_ROUTER_URL/api/auth/login" -H "Content-Type: application/json" -d "$body")" || code="000"
  if [ "$code" = "200" ]; then
    return 0
  fi
  echo "ERROR: 9router login failed (HTTP $code)." >&2
  echo "       INITIAL_PASSWORD in .env only applies on first boot; if the" >&2
  echo "       password was changed since, set up the combo/API key manually" >&2
  echo "       at $NINE_ROUTER_URL/dashboard. (Not retrying: 9router locks" >&2
  echo "       out after 5 wrong attempts.)" >&2
  return 1
}

_api() { # METHOD PATH [JSON]
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -fsS -b "$COOKIE_JAR" -X "$method" "$NINE_ROUTER_URL$path" \
      -H "Content-Type: application/json" -d "$data"
  else
    curl -fsS -b "$COOKIE_JAR" -X "$method" "$NINE_ROUTER_URL$path"
  fi
}

# update_env_var NAME VALUE — set/replace NAME=VALUE in ./.env (no sed
# escaping headaches with API keys that may contain slashes etc.)
update_env_var() {
  local name="$1" value="$2" tmp
  tmp="$(mktemp)"
  if grep -q "^${name}=" .env 2>/dev/null; then
    awk -v n="$name" -v v="$value" 'BEGIN{FS=OFS="="} $1==n{print n "=" v; next} {print}' .env > "$tmp"
  else
    cp .env "$tmp"
    printf '%s=%s\n' "$name" "$value" >> "$tmp"
  fi
  cat "$tmp" > .env
  rm -f "$tmp"
  chmod 600 .env
}

# _parse_models: reads NINE_ROUTER_MODELS (comma-separated), trims
# whitespace, drops empties. Fills the MODELS array (global, for simplicity).
_parse_models() {
  MODELS=()
  local raw="${NINE_ROUTER_MODELS:-}"
  [ -z "$raw" ] && return 0
  local IFS=','
  local item
  for item in $raw; do
    item="$(echo "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$item" ] && MODELS+=("$item")
  done
}

# _known_prefixes: union of connected built-in provider aliases (derived from
# existing /v1/models entries — the only generic way to get resolved aliases
# without hardcoding any provider list) and custom provider-node prefixes.
# Best-effort: used only for a sanity-check warning, never to block.
_known_prefixes() {
  local key="$1"
  {
    _api GET /api/provider-nodes 2>/dev/null | jq -r '.nodes[]?.prefix // empty'
    curl -fsS -H "Authorization: Bearer $key" "$NINE_ROUTER_URL/v1/models" 2>/dev/null \
      | jq -r '.data[]?.id // empty' | sed 's#/.*##'
  } | sort -u
}

_warn_unknown_prefixes() {
  local key="$1"; shift
  local known
  known="$(_known_prefixes "$key")"
  local m prefix found
  for m in "$@"; do
    prefix="${m%%/*}"
    found=0
    while IFS= read -r k; do [ "$k" = "$prefix" ] && found=1 && break; done <<< "$known"
    if [ "$found" -eq 0 ]; then
      echo "WARNING: '$m' — no connected provider found for prefix '$prefix'." >&2
      echo "         Add it in the dashboard first (Providers -> built-in, or" >&2
      echo "         'Add OpenAI/Anthropic Compatible' with prefix '$prefix')," >&2
      echo "         otherwise 9router will reject requests for this model" >&2
      echo "         with 'No active credentials for provider: $prefix'." >&2
    fi
  done
}

# Creates (or reuses) the 9router API key Hermes authenticates with.
# Exports NINE_ROUTER_API_KEY and persists it to .env. Sets HERMES_KEY_CHANGED=1
# when a new key was minted so install.sh knows to re-render Hermes's config.
_ensure_hermes_api_key() {
  HERMES_KEY_CHANGED=0
  if [ -n "${NINE_ROUTER_API_KEY:-}" ]; then
    echo "  combo-setup: reusing NINE_ROUTER_API_KEY from .env"
    return 0
  fi
  local resp key
  resp="$(_api POST /api/keys "$(jq -n --arg n "hermes-$(hostname -s 2>/dev/null || echo stb)" '{name:$n}')")" || {
    echo "ERROR: could not create a 9router API key for Hermes." >&2
    return 1
  }
  key="$(echo "$resp" | jq -r '.key // empty')"
  if [ -z "$key" ]; then
    echo "ERROR: 9router returned no API key." >&2
    return 1
  fi
  NINE_ROUTER_API_KEY="$key"
  export NINE_ROUTER_API_KEY
  update_env_var NINE_ROUTER_API_KEY "$key"
  HERMES_KEY_CHANGED=1
  export HERMES_KEY_CHANGED
  echo "  combo-setup: created API key for Hermes and saved it to .env (chmod 600)"
}

# run_combo_setup: the main entry point, called from install.sh after the
# 9router container is up. Reads NINE_ROUTER_MODELS / NINE_ROUTER_COMBO_NAME
# from the environment (i.e. from .env, already sourced by install.sh).
# Sets HERMES_MODEL_TARGET to whatever Hermes's model.default should be: the
# single model string (1 model configured) or the combo name (2+ models).
run_combo_setup() {
  _require_jq || return 1
  wait_for_9router || return 1
  _nine_router_login || return 1
  _ensure_hermes_api_key || return 1

  _parse_models
  HERMES_MODEL_TARGET=""

  if [ "${#MODELS[@]}" -eq 0 ]; then
    echo "WARNING: NINE_ROUTER_MODELS is empty in .env — skipping model/combo setup." >&2
    echo "         Connect a provider and list a model id in .env, or run" >&2
    echo "         'hermes model' inside the hermes container to configure it" >&2
    echo "         manually. See docs/PROVIDERS.md." >&2
    export HERMES_MODEL_TARGET
    return 1
  fi

  _warn_unknown_prefixes "$NINE_ROUTER_API_KEY" "${MODELS[@]}"

  if [ "${#MODELS[@]}" -eq 1 ]; then
    HERMES_MODEL_TARGET="${MODELS[0]}"
    echo "  combo-setup: single model configured (${MODELS[0]}) — no combo needed"
    export HERMES_MODEL_TARGET
    return 0
  fi

  local combo_name="${NINE_ROUTER_COMBO_NAME:-stb-default}"
  if _api GET /api/combos | jq -e --arg n "$combo_name" '.combos[]? | select(.name==$n)' >/dev/null 2>&1; then
    echo "  combo-setup: combo '$combo_name' already exists, leaving as-is"
  else
    # NOTE: do NOT send "kind" — in 9router it means service type
    # (llm/webSearch/webFetch); null = LLM. A made-up kind hides the combo
    # from /v1/models (found by live testing).
    local payload
    payload="$(jq -n --arg name "$combo_name" --argjson models "$(printf '%s\n' "${MODELS[@]}" | jq -R . | jq -s .)" \
      '{name:$name, models:$models}')"
    if _api POST /api/combos "$payload" >/dev/null 2>&1; then
      echo "  combo-setup: combo '$combo_name' created with tiers: ${MODELS[*]}"
    else
      echo "ERROR: failed to create combo '$combo_name'." >&2
      export HERMES_MODEL_TARGET
      return 1
    fi
  fi

  HERMES_MODEL_TARGET="$combo_name"
  export HERMES_MODEL_TARGET
}
