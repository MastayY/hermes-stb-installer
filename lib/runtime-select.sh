#!/usr/bin/env bash
# lib/runtime-select.sh: Container runtime abstraction and selection logic.

STATE_FILE_DEFAULT="${STATE_FILE_DEFAULT:-.runtime}"

runtime_determine() {
    local requested="${1:-}"

    if [[ -n "${requested}" ]]; then
        case "${requested}" in
            podman|docker)
                echo "${requested}"
                return 0
                ;;
            *)
                echo "ERROR: Invalid runtime requested: '${requested}'. Choose 'podman' or 'docker'." >&2
                return 1
                ;;
        esac
    fi

    # Check if a previously selected runtime state exists
    if [[ -f "${STATE_FILE_DEFAULT}" ]]; then
        local saved
        saved="$(cat "${STATE_FILE_DEFAULT}" 2>/dev/null | tr -d '[:space:]')"
        if [[ "${saved}" == "podman" || "${saved}" == "docker" ]]; then
            echo "${saved}"
            return 0
        fi
    fi

    # Default runtime is podman
    echo "podman"
    return 0
}

runtime_save_state() {
    local runtime="$1"
    local state_file="${2:-${STATE_FILE_DEFAULT}}"

    if [[ "${RUNTIME_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Saved runtime state '${runtime}' to '${state_file}'"
        return 0
    fi

    echo "${runtime}" > "${state_file}"
    chmod 600 "${state_file}"
}

runtime_load_state() {
    local state_file="${1:-${STATE_FILE_DEFAULT}}"
    if [[ -f "${state_file}" ]]; then
        cat "${state_file}" 2>/dev/null | tr -d '[:space:]'
    else
        echo ""
    fi
}

runtime_detect_installed() {
    local runtime="$1"
    command -v "${runtime}" >/dev/null 2>&1
}

# Find the best available compose command for the selected runtime
get_compose_command() {
    local runtime="$1"

    if [[ "${runtime}" == "podman" ]]; then
        # Check if 'podman compose' is functional
        if podman compose version >/dev/null 2>&1; then
            echo "podman compose"
            return 0
        elif command -v podman-compose >/dev/null 2>&1; then
            echo "podman-compose"
            return 0
        fi
    elif [[ "${runtime}" == "docker" ]]; then
        if docker compose version >/dev/null 2>&1; then
            echo "docker compose"
            return 0
        elif command -v docker-compose >/dev/null 2>&1; then
            echo "docker-compose"
            return 0
        fi
    fi

    return 1
}

# Install runtime package via apt if missing
runtime_install_package() {
    local runtime="$1"

    if runtime_detect_installed "${runtime}"; then
        echo "Runtime '${runtime}' is already installed."
        return 0
    fi

    echo "Runtime '${runtime}' is not installed. Attempting installation via package manager..."

    if [[ "${RUNTIME_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Simulated installation of package '${runtime}'"
        return 0
    fi

    local cmd_prefix=""
    if [[ ${EUID} -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            cmd_prefix="sudo"
        else
            echo "ERROR: Root privileges or sudo required to install packages." >&2
            return 1
        fi
    fi

    if command -v apt-get >/dev/null 2>&1; then
        ${cmd_prefix} apt-get update -y
        if [[ "${runtime}" == "podman" ]]; then
            ${cmd_prefix} apt-get install -y podman podman-compose slirp4netns uidmap
        elif [[ "${runtime}" == "docker" ]]; then
            ${cmd_prefix} apt-get install -y docker.io docker-compose-plugin
            ${cmd_prefix} systemctl enable --now docker
        fi
    else
        echo "ERROR: Unsupported package manager. Please install '${runtime}' manually." >&2
        return 1
    fi

    if ! runtime_detect_installed "${runtime}"; then
        echo "ERROR: Installation of '${runtime}' completed, but executable was not found." >&2
        return 1
    fi

    echo "Installation of '${runtime}' completed successfully."
    return 0
}

# Execute a compose command with the active runtime
container_compose_exec() {
    local runtime="$1"
    shift
    local compose_args=("$@")

    if [[ "${RUNTIME_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Compose execution (${runtime}): ${compose_args[*]}"
        return 0
    fi

    local compose_cmd
    compose_cmd="$(get_compose_command "${runtime}" 2>/dev/null || true)"

    if [[ -z "${compose_cmd}" ]]; then
        echo "ERROR: No compatible compose tool found for runtime '${runtime}'." >&2
        return 1
    fi

    # Execute
    ${compose_cmd} "${compose_args[@]}"
}

# Execute raw runtime command
container_runtime_exec() {
    local runtime="$1"
    shift
    local args=("$@")

    if [[ "${RUNTIME_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Runtime execution (${runtime}): ${args[*]}"
        return 0
    fi

    "${runtime}" "${args[@]}"
}
