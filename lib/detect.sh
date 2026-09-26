#!/usr/bin/env bash
# lib/detect.sh: Hardware, OS, and runtime detection for Hermes + 9Router installer.

# Prevent direct exit when sourced
detect_init_vars() {
    DETECT_ARCH=""
    DETECT_ARCH_SUPPORTED=false
    DETECT_RAM_MB=0
    DETECT_RAM_GB=0
    DETECT_IS_LOW_RAM=false
    DETECT_DISTRO_ID=""
    DETECT_DISTRO_VERSION=""
    DETECT_DISTRO_NAME=""
    DETECT_IS_ARMBIAN=false
    DETECT_SYSTEMD_ACTIVE=false
}

detect_architecture() {
    local raw_arch
    raw_arch="$(uname -m 2>/dev/null || echo "unknown")"
    case "${raw_arch}" in
        aarch64|arm64)
            DETECT_ARCH="aarch64"
            DETECT_ARCH_SUPPORTED=true
            ;;
        x86_64|amd64)
            DETECT_ARCH="x86_64"
            DETECT_ARCH_SUPPORTED=true
            ;;
        armv7l|armhf|armv8l)
            DETECT_ARCH="armv7l"
            DETECT_ARCH_SUPPORTED=false
            ;;
        *)
            DETECT_ARCH="${raw_arch}"
            DETECT_ARCH_SUPPORTED=false
            ;;
    esac
}

detect_memory() {
    local mem_kb=0
    if [[ -f /proc/meminfo ]]; then
        mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    elif command -v free >/dev/null 2>&1; then
        mem_kb="$(free -k | awk 'NR==2{print $2}' 2>/dev/null || echo 0)"
    fi

    DETECT_RAM_MB=$((mem_kb / 1024))
    DETECT_RAM_GB=$((DETECT_RAM_MB / 1024))

    # Low RAM threshold: <= 2048 MB (2 GB)
    if [[ ${DETECT_RAM_MB} -le 2048 ]]; then
        DETECT_IS_LOW_RAM=true
    else
        DETECT_IS_LOW_RAM=false
    fi
}

detect_distribution() {
    if [[ -f /etc/armbian-release ]]; then
        DETECT_IS_ARMBIAN=true
    fi

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DETECT_DISTRO_ID="${ID:-unknown}"
        DETECT_DISTRO_VERSION="${VERSION_ID:-unknown}"
        DETECT_DISTRO_NAME="${PRETTY_NAME:-${ID:-Linux}}"
    else
        DETECT_DISTRO_ID="unknown"
        DETECT_DISTRO_VERSION="unknown"
        DETECT_DISTRO_NAME="Unknown Linux"
    fi

    # Check systemd availability
    if [[ -d /run/systemd/system ]]; then
        DETECT_SYSTEMD_ACTIVE=true
    else
        DETECT_SYSTEMD_ACTIVE=false
    fi
}

# Run smoke test on the chosen container runtime.
# This validates kernel support for cgroups, overlayfs, and namespaces.
detect_smoke_test_runtime() {
    local runtime="$1"
    local test_image="hello-world"

    if ! command -v "${runtime}" >/dev/null 2>&1; then
        echo "ERROR: Runtime executable '${runtime}' was not found in PATH." >&2
        return 1
    fi

    echo "Running container smoke test with '${runtime}' (${test_image})..."

    local output
    local status=0
    output="$("${runtime}" run --rm "${test_image}" 2>&1)" || status=$?

    if [[ ${status} -ne 0 ]]; then
        echo "ERROR: Runtime smoke test failed with exit code ${status}." >&2
        echo "Diagnostic output:" >&2
        echo "${output}" >&2

        # Diagnose common STB kernel limitations
        if echo "${output}" | grep -iq "overlay"; then
            echo "DIAGNOSIS: The host kernel lacks proper overlayfs or storage-driver support." >&2
            echo "FIX: Ensure the overlay kernel module is loaded ('sudo modprobe overlay') or switch storage driver." >&2
        elif echo "${output}" | grep -iq "cgroup"; then
            echo "DIAGNOSIS: Cgroups controller error detected. STB kernels may require cgroup v2 enable." >&2
            echo "FIX: Add 'systemd.unified_cgroup_hierarchy=1' to /boot/armbianEnv.txt or kernel cmdline." >&2
        elif echo "${output}" | grep -iq "permission denied"; then
            echo "DIAGNOSIS: Subuid/subgid mapping or socket permissions are not configured for this user." >&2
            echo "FIX: Verify /etc/subuid and /etc/subgid entries for $(whoami)." >&2
        fi
        return 1
    fi

    echo "Runtime smoke test passed successfully."
    return 0
}

run_preflight_checks() {
    detect_init_vars
    detect_architecture
    detect_memory
    detect_distribution

    echo "=========================================================="
    echo "            Preflight System Detection Check              "
    echo "=========================================================="
    echo "Architecture     : ${DETECT_ARCH}"
    echo "Operating System : ${DETECT_DISTRO_NAME}"
    echo "Armbian Detected : ${DETECT_IS_ARMBIAN}"
    echo "Total Memory     : ${DETECT_RAM_MB} MB (~${DETECT_RAM_GB} GB)"
    echo "Low-RAM Profile  : ${DETECT_IS_LOW_RAM}"
    echo "Systemd Active   : ${DETECT_SYSTEMD_ACTIVE}"
    echo "=========================================================="

    if [[ "${DETECT_ARCH_SUPPORTED}" != "true" ]]; then
        echo "CRITICAL ERROR: Architecture '${DETECT_ARCH}' is not supported." >&2
        if [[ "${DETECT_ARCH}" == "armv7l" ]]; then
            echo "Reason: 32-bit ARM cannot execute upstream 64-bit container images." >&2
            echo "Solution: Flash a 64-bit (aarch64/arm64) Armbian or Debian image onto your STB." >&2
        else
            echo "Reason: Only aarch64 (ARM 64-bit) and x86_64 (AMD64) are supported." >&2
        fi
        return 1
    fi

    if [[ "${DETECT_SYSTEMD_ACTIVE}" != "true" ]]; then
        echo "WARNING: Systemd does not appear to be active. Automated background service" >&2
        echo "supervision requires systemd. You may need to manage processes manually." >&2
    fi

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_preflight_checks
fi
