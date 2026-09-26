#!/usr/bin/env bash
# lib/docker-fix.sh: Mitigations for Docker rootful runtime (UFW rules and log rotation).

DOCKER_DAEMON_JSON="${DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}"
UFW_AFTER_RULES="${UFW_AFTER_RULES:-/etc/ufw/after.rules}"
UFW_MARKER_START="# BEGIN HERMES STB UFW DOCKER USER"
UFW_MARKER_END="# END HERMES STB UFW DOCKER USER"

docker_apply_daemon_json() {
    local daemon_path="${DOCKER_DAEMON_JSON}"

    echo "Configuring Docker daemon log rotation to prevent disk exhaustion..."

    if [[ "${DOCKER_FIX_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Configured log rotation in ${daemon_path}"
        return 0
    fi

    local target_dir
    target_dir="$(dirname "${daemon_path}")"
    local cmd_prefix=""
    if [[ ! -w "${target_dir}" || ( -e "${daemon_path}" && ! -w "${daemon_path}" ) ]]; then
        if [[ ${EUID} -ne 0 ]]; then
            if command -v sudo >/dev/null 2>&1; then
                cmd_prefix="sudo"
            else
                echo "ERROR: Root privileges or sudo required to modify ${daemon_path}." >&2
                return 1
            fi
        fi
    fi

    ${cmd_prefix} mkdir -p "$(dirname "${daemon_path}")"

    # Merge or create JSON configuration
    local temp_json
    temp_json="$(mktemp)"

    if [[ -f "${daemon_path}" && -s "${daemon_path}" ]]; then
        # Merge using python3
        python3 -c "
import json, sys
try:
    with open('${daemon_path}', 'r') as f:
        data = json.load(f)
except Exception:
    data = {}
data['log-driver'] = 'json-file'
if 'log-opts' not in data:
    data['log-opts'] = {}
data['log-opts']['max-size'] = '10m'
data['log-opts']['max-file'] = '3'
with open('${temp_json}', 'w') as f:
    json.dump(data, f, indent=2)
"
    else
        cat > "${temp_json}" <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    fi

    ${cmd_prefix} cp "${temp_json}" "${daemon_path}"
    ${cmd_prefix} chmod 644 "${daemon_path}"
    rm -f "${temp_json}"

    if [[ "${DOCKER_FIX_SKIP_RELOAD:-false}" != "true" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet docker 2>/dev/null; then
                echo "Reloading Docker daemon configuration..."
                ${cmd_prefix} systemctl reload docker 2>/dev/null || ${cmd_prefix} systemctl restart docker 2>/dev/null || true
            fi
        fi
    fi

    echo "Docker daemon log rotation applied successfully."
    return 0
}

docker_apply_ufw_rules() {
    local rules_path="${UFW_AFTER_RULES}"

    if [[ "${DOCKER_FIX_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Applied UFW DOCKER-USER protection rules to ${rules_path}"
        return 0
    fi

    if ! command -v ufw >/dev/null 2>&1; then
        # UFW is not installed; no rule patch needed
        return 0
    fi

    if [[ ! -f "${rules_path}" ]]; then
        return 0
    fi

    echo "Checking UFW and Docker iptables coexistence..."

    if grep -qs "${UFW_MARKER_START}" "${rules_path}"; then
        echo "UFW DOCKER-USER rules are already present in ${rules_path}."
        return 0
    fi

    local target_dir
    target_dir="$(dirname "${rules_path}")"
    local cmd_prefix=""
    if [[ ! -w "${target_dir}" || ( -e "${rules_path}" && ! -w "${rules_path}" ) ]]; then
        if [[ ${EUID} -ne 0 ]]; then
            if command -v sudo >/dev/null 2>&1; then
                cmd_prefix="sudo"
            else
                echo "ERROR: Root privileges or sudo required to modify ${rules_path}." >&2
                return 1
            fi
        fi
    fi

    echo "Applying safe DOCKER-USER rules to ${rules_path} to prevent UFW bypass..."

    local temp_rules
    temp_rules="$(mktemp)"

    cat "${rules_path}" > "${temp_rules}"

    cat >> "${temp_rules}" <<EOF

${UFW_MARKER_START}
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A DOCKER-USER -s 127.0.0.0/8 -j ACCEPT
-A DOCKER-USER -s 10.0.0.0/8 -j ACCEPT
-A DOCKER-USER -s 172.16.0.0/12 -j ACCEPT
-A DOCKER-USER -s 192.168.0.0/16 -j ACCEPT
-A DOCKER-USER -j RETURN
COMMIT
${UFW_MARKER_END}
EOF

    ${cmd_prefix} cp "${temp_rules}" "${rules_path}"
    rm -f "${temp_rules}"

    if [[ "${DOCKER_FIX_SKIP_RELOAD:-false}" != "true" ]] && command -v ufw >/dev/null 2>&1; then
        if ${cmd_prefix} ufw status | grep -qi "Status: active"; then
            echo "Reloading UFW firewall..."
            ${cmd_prefix} ufw reload >/dev/null 2>&1 || true
        fi
    fi

    echo "UFW DOCKER-USER rules successfully applied."
    return 0
}

docker_revert_ufw_rules() {
    local rules_path="${UFW_AFTER_RULES}"

    if [[ "${DOCKER_FIX_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Reverted UFW DOCKER-USER protection rules from ${rules_path}"
        return 0
    fi

    if [[ ! -f "${rules_path}" ]]; then
        return 0
    fi

    if ! grep -qs "${UFW_MARKER_START}" "${rules_path}"; then
        return 0
    fi

    local target_dir
    target_dir="$(dirname "${rules_path}")"
    local cmd_prefix=""
    if [[ ! -w "${target_dir}" || ( -e "${rules_path}" && ! -w "${rules_path}" ) ]]; then
        if [[ ${EUID} -ne 0 ]]; then
            if command -v sudo >/dev/null 2>&1; then
                cmd_prefix="sudo"
            else
                echo "ERROR: Root privileges or sudo required to revert ${rules_path}." >&2
                return 1
            fi
        fi
    fi

    echo "Removing DOCKER-USER rules from ${rules_path}..."
    ${cmd_prefix} sed -i "/${UFW_MARKER_START}/,/${UFW_MARKER_END}/d" "${rules_path}"

    if command -v ufw >/dev/null 2>&1; then
        if ${cmd_prefix} ufw status 2>/dev/null | grep -qi "Status: active"; then
            ${cmd_prefix} ufw reload >/dev/null 2>&1 || true
        fi
    fi

    echo "UFW rules successfully reverted."
    return 0
}
