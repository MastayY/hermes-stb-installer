#!/usr/bin/env bash
# lib/docker-fix.sh — UFW/iptables interaction fix + log rotation for Docker.
# Meant to be sourced by install.sh, not executed directly. Only called
# when CONTAINER_RUNTIME=docker.
#
# WHY THIS EXISTS: dockerd runs as root and inserts its own DOCKER-USER
# iptables chain directly, ahead of/bypassing UFW's own rules unless UFW is
# explicitly told to route through it. This is exactly the class of bug that
# previously locked out an STB in this project's history — this fix must be
# applied BEFORE the first container starts, not after.
#
# Pattern used below (adding a DOCKER-USER block to /etc/ufw/after.rules
# that routes through ufw-user-forward) is the widely-documented community
# fix for this interaction. It has NOT been re-verified against current
# Docker/UFW source for this project — because
# a bad iptables edit is exactly what caused the original incident, this
# function backs up the original file first and is written to be idempotent
# (safe to run more than once) rather than assumed correct outright.

UFW_AFTER_RULES="/etc/ufw/after.rules"
UFW_MARKER_BEGIN="# BEGIN hermes-stb-installer DOCKER-USER FIX"
UFW_MARKER_END="# END hermes-stb-installer DOCKER-USER FIX"

apply_docker_ufw_fix() {
  if ! command -v ufw >/dev/null 2>&1; then
    echo "  Docker/UFW fix: ufw not installed, nothing to do"
    return 0
  fi

  if [ ! -f "$UFW_AFTER_RULES" ]; then
    echo "WARNING: $UFW_AFTER_RULES not found — skipping UFW/Docker fix." >&2
    echo "         If you use UFW, apply the DOCKER-USER fix manually." >&2
    return 0
  fi

  if grep -qF "$UFW_MARKER_BEGIN" "$UFW_AFTER_RULES" 2>/dev/null; then
    echo "  Docker/UFW fix: already applied (marker found), skipping"
    return 0
  fi

  local ts backup
  ts="$(date +%Y%m%d%H%M%S)"
  backup="${UFW_AFTER_RULES}.pre-hermes9router.${ts}"
  cp -p "$UFW_AFTER_RULES" "$backup"
  echo "  Docker/UFW fix: backed up $UFW_AFTER_RULES to $backup"

  cat >> "$UFW_AFTER_RULES" <<EOF

$UFW_MARKER_BEGIN
*filter
:ufw-user-forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j RETURN --src 10.0.0.0/8
-A DOCKER-USER -j RETURN --src 172.16.0.0/12
-A DOCKER-USER -j RETURN --src 192.168.0.0/16
-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN
-A DOCKER-USER -j RETURN
COMMIT
$UFW_MARKER_END
EOF

  echo "  Docker/UFW fix: block appended. Reloading UFW..."
  if ! ufw reload; then
    echo "ERROR: 'ufw reload' failed after editing $UFW_AFTER_RULES." >&2
    echo "       Restoring from backup: $backup" >&2
    cp -p "$backup" "$UFW_AFTER_RULES"
    ufw reload || true
    return 1
  fi
  echo "  Docker/UFW fix: applied and UFW reloaded successfully"
}

# revert_docker_ufw_fix: called by uninstall.sh
revert_docker_ufw_fix() {
  if [ ! -f "$UFW_AFTER_RULES" ]; then
    return 0
  fi
  if ! grep -qF "$UFW_MARKER_BEGIN" "$UFW_AFTER_RULES" 2>/dev/null; then
    return 0
  fi
  echo "  Docker/UFW fix: removing installer's block from $UFW_AFTER_RULES"
  sed -i "/$UFW_MARKER_BEGIN/,/$UFW_MARKER_END/d" "$UFW_AFTER_RULES"
  ufw reload || true
}

apply_docker_log_rotation() {
  local daemon_json="/etc/docker/daemon.json"
  mkdir -p /etc/docker

  if [ -f "$daemon_json" ] && grep -q '"log-driver"' "$daemon_json" 2>/dev/null; then
    echo "  Docker log rotation: daemon.json already configures a log-driver, leaving as-is"
    return 0
  fi

  if [ -f "$daemon_json" ] && [ -s "$daemon_json" ]; then
    local ts backup
    ts="$(date +%Y%m%d%H%M%S)"
    backup="${daemon_json}.pre-hermes9router.${ts}"
    cp -p "$daemon_json" "$backup"
    echo "  Docker log rotation: existing daemon.json backed up to $backup"
    echo "WARNING: daemon.json already has content — merge log-driver settings" >&2
    echo "         manually instead of letting this script overwrite it." >&2
    return 0
  fi

  cat > "$daemon_json" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
  echo "  Docker log rotation: wrote $daemon_json (max-size=10m, max-file=3)"
  echo "  Docker log rotation: restarting docker service to apply..."
  systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || \
    echo "WARNING: could not restart docker automatically — restart it manually." >&2
}
