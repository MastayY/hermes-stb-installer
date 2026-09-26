#!/usr/bin/env bash
# lib/swap.sh: Automated swapfile management for low-RAM devices (STB Homelab).

# Default configurations
SWAP_FILE_PATH="${SWAP_FILE_PATH:-/swapfile}"
SWAP_THRESHOLD_MB="${SWAP_THRESHOLD_MB:-2048}"
SWAP_DEFAULT_SIZE_MB="${SWAP_DEFAULT_SIZE_MB:-2048}"
SWAP_SAFETY_BUFFER_MB="${SWAP_SAFETY_BUFFER_MB:-1024}"

# Calculate appropriate swap size based on total RAM
calculate_recommended_swap_size() {
    local ram_mb="$1"
    if [[ ${ram_mb} -le 1024 ]]; then
        echo 2048
    elif [[ ${ram_mb} -le 2048 ]]; then
        echo 2048
    elif [[ ${ram_mb} -le 4096 ]]; then
        echo 1024
    else
        echo 0
    fi
}

# Check current active swap across the system in MB
get_active_swap_mb() {
    local total_kb=0
    if [[ -f /proc/meminfo ]]; then
        total_kb="$(awk '/SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    elif command -v free >/dev/null 2>&1; then
        total_kb="$(free -k | awk '/Swap:/ {print $2}' 2>/dev/null || echo 0)"
    fi
    echo $((total_kb / 1024))
}

# Check free disk space in MB on the target path's mountpoint
get_available_disk_mb() {
    local target_dir
    target_dir="$(dirname "$1")"
    if [[ ! -d "${target_dir}" ]]; then
        target_dir="/"
    fi
    df -m "${target_dir}" | awk 'NR==2 {print $4}'
}

# Determine whether swap should be configured
should_configure_swap() {
    local ram_mb="$1"
    local no_swap_flag="${2:-false}"

    if [[ "${no_swap_flag}" == "true" ]]; then
        return 1
    fi

    if [[ ${ram_mb} -gt ${SWAP_THRESHOLD_MB} ]]; then
        return 1
    fi

    local current_swap
    current_swap="$(get_active_swap_mb)"
    if [[ ${current_swap} -ge ${SWAP_DEFAULT_SIZE_MB} ]]; then
        return 1
    fi

    return 0
}

# Setup and activate swapfile
swap_setup() {
    local ram_mb="$1"
    local no_swap_flag="${2:-false}"
    local swap_path="${SWAP_FILE_PATH}"

    if [[ "${no_swap_flag}" == "true" ]]; then
        echo "Swap management skipped: --no-swap flag requested."
        return 0
    fi

    local current_swap
    current_swap="$(get_active_swap_mb)"
    if [[ ${current_swap} -ge ${SWAP_DEFAULT_SIZE_MB} ]]; then
        echo "Active swap already sufficient (${current_swap} MB detected). No new swapfile needed."
        return 0
    fi

    if [[ ${ram_mb} -gt ${SWAP_THRESHOLD_MB} ]]; then
        echo "System RAM (${ram_mb} MB) exceeds threshold (${SWAP_THRESHOLD_MB} MB). Swap creation not required."
        return 0
    fi

    local recommended_size_mb
    recommended_size_mb="$(calculate_recommended_swap_size "${ram_mb}")"
    if [[ ${recommended_size_mb} -le 0 ]]; then
        echo "Recommended swap size is 0 MB. Skipping."
        return 0
    fi

    echo "Configuring ${recommended_size_mb} MB swapfile at ${swap_path}..."

    # Check disk space
    local free_disk_mb
    free_disk_mb="$(get_available_disk_mb "${swap_path}")"
    local required_disk_mb=$((recommended_size_mb + SWAP_SAFETY_BUFFER_MB))

    if [[ ${free_disk_mb} -lt ${required_disk_mb} ]]; then
        echo "WARNING: Insufficient storage space on disk. Free: ${free_disk_mb} MB, Required: ${required_disk_mb} MB." >&2
        echo "Skipping swapfile creation to prevent filling the storage drive." >&2
        return 0
    fi

    # Dry-run support for testing or non-root validation
    if [[ "${SWAP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Swap setup validated successfully (Target: ${swap_path}, Size: ${recommended_size_mb} MB)."
        return 0
    fi

    # Require root or sudo privileges
    local cmd_prefix=""
    if [[ ${EUID} -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            cmd_prefix="sudo"
        else
            echo "ERROR: Root privileges or sudo required to allocate swapfile." >&2
            return 1
        fi
    fi

    # If swapfile already exists and is active
    if [[ -f "${swap_path}" ]]; then
        if swapon --show 2>/dev/null | grep -q "${swap_path}"; then
            echo "Swapfile ${swap_path} is already active."
            return 0
        fi
    fi

    # Allocate file using fallocate, with dd fallback
    echo "Allocating swap storage..."
    if ! ${cmd_prefix} fallocate -l "${recommended_size_mb}M" "${swap_path}" 2>/dev/null; then
        echo "fallocate failed, falling back to dd..."
        ${cmd_prefix} dd if=/dev/zero of="${swap_path}" bs=1M count="${recommended_size_mb}" status=progress
    fi

    ${cmd_prefix} chmod 600 "${swap_path}"
    ${cmd_prefix} mkswap "${swap_path}" >/dev/null
    ${cmd_prefix} swapon "${swap_path}"

    # Persist in /etc/fstab if not present
    local fstab_entry="${swap_path} none swap sw 0 0"
    if ! grep -qs "^[[:space:]]*${swap_path}[[:space:]]" /etc/fstab; then
        echo "Adding swap entry to /etc/fstab..."
        echo "${fstab_entry}" | ${cmd_prefix} tee -a /etc/fstab >/dev/null
    fi

    echo "Swapfile successfully created and activated (${recommended_size_mb} MB)."
    return 0
}

# Deactivate and remove swapfile
swap_remove() {
    local swap_path="${SWAP_FILE_PATH}"

    if [[ "${SWAP_DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] Swap removal validated for ${swap_path}."
        return 0
    fi

    local cmd_prefix=""
    if [[ ${EUID} -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            cmd_prefix="sudo"
        else
            echo "ERROR: Root privileges or sudo required to remove swapfile." >&2
            return 1
        fi
    fi

    if [[ -f "${swap_path}" ]]; then
        echo "Deactivating swapfile ${swap_path}..."
        ${cmd_prefix} swapoff "${swap_path}" 2>/dev/null || true
        echo "Removing swapfile from disk..."
        ${cmd_prefix} rm -f "${swap_path}"
    fi

    if [[ -f /etc/fstab ]] && grep -qs "${swap_path}" /etc/fstab; then
        echo "Removing swap entry from /etc/fstab..."
        ${cmd_prefix} sed -i "\|${swap_path}|d" /etc/fstab
    fi

    echo "Swap removal complete."
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    target_ram="${1:-1024}"
    target_noswap="${2:-false}"
    swap_setup "${target_ram}" "${target_noswap}"
fi
