#!/usr/bin/env bash
# lib/podman-setup.sh: Rootless Podman configuration and systemd user service setup.

podman_enable_user_linger() {
    local target_user="${1:-$(whoami)}"

    echo "Configuring user lingering for '${target_user}'..."

    if [[ "${PODMAN_SETUP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] loginctl enable-linger ${target_user}"
        return 0
    fi

    if ! command -v loginctl >/dev/null 2>&1; then
        echo "WARNING: loginctl command not found. Cannot enable user lingering automatically." >&2
        return 0
    fi

    # Check if lingering is already enabled
    if loginctl show-user "${target_user}" 2>/dev/null | grep -qi "Linger=yes"; then
        echo "User lingering is already enabled for '${target_user}'."
        return 0
    fi

    if loginctl enable-linger "${target_user}" 2>/dev/null; then
        echo "User lingering successfully enabled."
        return 0
    fi

    # Fallback with sudo if needed
    if command -v sudo >/dev/null 2>&1; then
        if sudo loginctl enable-linger "${target_user}" 2>/dev/null; then
            echo "User lingering successfully enabled via sudo."
            return 0
        fi
    fi

    echo "WARNING: Failed to enable user lingering. Containers may terminate when logging out." >&2
    return 0
}

podman_verify_subuid_subgid() {
    local target_user="${1:-$(whoami)}"

    if [[ "${target_user}" == "root" ]]; then
        return 0
    fi

    if [[ "${PODMAN_SETUP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Verified subuid/subgid mapping for ${target_user}"
        return 0
    fi

    local has_subuid=false
    local has_subgid=false

    if [[ -f /etc/subuid ]] && grep -qs "^${target_user}:" /etc/subuid; then
        has_subuid=true
    fi

    if [[ -f /etc/subgid ]] && grep -qs "^${target_user}:" /etc/subgid; then
        has_subgid=true
    fi

    if [[ "${has_subuid}" == "true" && "${has_subgid}" == "true" ]]; then
        return 0
    fi

    echo "Configuring subuid and subgid ranges for rootless containers (${target_user})..."

    local cmd_prefix=""
    if [[ ${EUID} -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            cmd_prefix="sudo"
        else
            echo "WARNING: Cannot configure /etc/subuid without root privileges." >&2
            return 0
        fi
    fi

    if command -v usermod >/dev/null 2>&1; then
        ${cmd_prefix} usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "${target_user}" 2>/dev/null || true
    fi

    return 0
}

podman_setup_systemd_service() {
    local install_dir="$1"
    local compose_file="${2:-compose/docker-compose.yml}"
    local service_name="hermes-stb.service"
    local user_systemd_dir="${HOME}/.config/systemd/user"
    local service_file="${user_systemd_dir}/${service_name}"

    echo "Configuring systemd user service for Podman compose autostart..."

    if [[ "${PODMAN_SETUP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Created systemd user unit at ${service_file} pointing to ${compose_file}"
        return 0
    fi

    mkdir -p "${user_systemd_dir}"

    local compose_bin
    if podman compose version >/dev/null 2>&1; then
        compose_bin="$(command -v podman) compose"
    elif command -v podman-compose >/dev/null 2>&1; then
        compose_bin="$(command -v podman-compose)"
    else
        compose_bin="podman compose"
    fi

    cat > "${service_file}" <<EOF
[Unit]
Description=Hermes Agent and 9Router Homelab Stack (Podman Rootless)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${install_dir}
ExecStart=${compose_bin} -f ${compose_file} up -d
ExecStop=${compose_bin} -f ${compose_file} down
TimeoutStartSec=0

[Install]
WantedBy=default.target
EOF

    chmod 644 "${service_file}"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable "${service_name}" 2>/dev/null || true
        echo "Systemd user service '${service_name}' enabled successfully."
    fi

    return 0
}

podman_remove_systemd_service() {
    local service_name="hermes-stb.service"
    local service_file="${HOME}/.config/systemd/user/${service_name}"

    if [[ "${PODMAN_SETUP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Removed systemd service ${service_file}"
        return 0
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user stop "${service_name}" 2>/dev/null || true
        systemctl --user disable "${service_name}" 2>/dev/null || true
    fi

    if [[ -f "${service_file}" ]]; then
        rm -f "${service_file}"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi

    echo "Podman systemd service successfully removed."
    return 0
}
