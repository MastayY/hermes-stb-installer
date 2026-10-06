#!/usr/bin/env bash
# lib/healthcheck.sh — post-install verification + final summary.
# Meant to be sourced by install.sh, not executed directly.

check_9router_health() {
  curl -fsS "${BASE_URL:-http://localhost:20128}/api/health" 2>/dev/null | grep -q '"ok":true'
}

check_hermes_running() {
  "$CONTAINER_RUNTIME" ps --filter "name=hermes" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q hermes
}

print_install_summary() {
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -z "$ip" ] && ip="<device-ip>"

  echo
  echo "=================================================================="
  echo " hermes-stb-installer — install summary"
  echo "=================================================================="
  echo " Runtime         : $CONTAINER_RUNTIME"
  echo " Hermes mode     : ${HERMES_MODE:-lite}"
  echo " 9router dashboard: http://${ip}:20128/dashboard  (LAN only by default)"
  echo " 9router API     : http://${ip}:20128/v1  (used internally by Hermes)"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    echo " Telegram bot    : configured — message it directly on Telegram"
  else
    echo " Telegram bot    : NOT configured (TELEGRAM_BOT_TOKEN empty in .env)"
  fi
  echo
  echo " Active model(s)   : ${HERMES_MODEL_TARGET:-<not set — see NINE_ROUTER_MODELS in .env>}"
  echo " Change model(s)   : edit NINE_ROUTER_MODELS in .env and re-run ./install.sh,"
  echo "                     or use the 9router dashboard directly"
  echo
  echo " View logs:"
  echo "   $CONTAINER_RUNTIME logs -f 9router"
  echo "   $CONTAINER_RUNTIME logs -f hermes"
  echo
  echo " Uninstall:"
  echo "   ./uninstall.sh"
  echo "=================================================================="
}

run_post_install_healthcheck() {
  echo "  healthcheck: checking 9router..."
  local ok9=0 okh=0
  for _ in $(seq 1 15); do
    check_9router_health && { ok9=1; break; }
    sleep 2
  done
  [ "$ok9" = "1" ] && echo "  healthcheck: 9router OK" || echo "WARNING: 9router health check did not pass — check '$CONTAINER_RUNTIME logs 9router'" >&2

  echo "  healthcheck: checking hermes container is running..."
  check_hermes_running && { okh=1; echo "  healthcheck: hermes OK"; } || echo "WARNING: hermes container not running — check '$CONTAINER_RUNTIME logs hermes'" >&2

  print_install_summary

  [ "$ok9" = "1" ] && [ "$okh" = "1" ]
}
