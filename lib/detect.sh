#!/usr/bin/env bash
# lib/detect.sh — architecture / RAM / distro detection.
# Meant to be sourced by install.sh, not executed directly.

# detect_arch: sets ARCH to one of aarch64 | armv7 | x86_64 | unknown
detect_arch() {
  local raw
  raw="$(uname -m)"
  case "$raw" in
    aarch64|arm64)
      ARCH="aarch64"
      ;;
    armv7l|armv6l)
      ARCH="armv7"
      ;;
    x86_64|amd64)
      ARCH="x86_64"
      ;;
    *)
      ARCH="unknown"
      ;;
  esac
  export ARCH
}

# detect_ram_mb: sets RAM_TOTAL_MB to total system RAM in MiB
detect_ram_mb() {
  local kb
  kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  RAM_TOTAL_MB=$(( kb / 1024 ))
  export RAM_TOTAL_MB
}

# detect_distro: sets DISTRO_ID and DISTRO_VERSION from /etc/os-release
detect_distro() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
  else
    DISTRO_ID="unknown"
    DISTRO_VERSION="unknown"
  fi
  export DISTRO_ID DISTRO_VERSION
}

# detect_disk_free_mb: sets DISK_FREE_MB to free storage in MiB on /var/lib/containers or /
detect_disk_free_mb() {
  local target_dir="/var/lib/containers"
  [ -d "$target_dir" ] || target_dir="/"
  local mb
  mb="$(df -m "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')"
  DISK_FREE_MB="${mb:-0}"
  export DISK_FREE_MB
}

# print_detect_summary: human-readable summary of everything detected above.
# Call detect_arch / detect_ram_mb / detect_disk_free_mb / detect_distro first.
print_detect_summary() {
  echo "  Architecture : ${ARCH:-unknown} (raw: $(uname -m))"
  echo "  Total RAM    : ${RAM_TOTAL_MB:-?} MB"
  echo "  Free Disk    : ${DISK_FREE_MB:-?} MB (~$(( ${DISK_FREE_MB:-0} / 1024 )) GB free)"
  echo "  Distro       : ${DISTRO_ID:-unknown} ${DISTRO_VERSION:-}"
}

# warn_low_disk_space: checks if free disk is below MIN_DISK_MB (default 5500 MB)
warn_low_disk_space() {
  local min_mb="${1:-5500}"
  if [ "${DISK_FREE_MB:-0}" -lt "$min_mb" ]; then
    echo "WARNING: Low disk space detected (${DISK_FREE_MB:-0} MB free)." >&2
    echo "         Hermes Agent (~3.9 GB uncompressed) and 9Router (~500 MB)" >&2
    echo "         require at least ${min_mb} MB (~5.5 GB) during download and layer extraction." >&2
    echo "         Recommended actions before proceeding:" >&2
    echo "           1. Clean container cache: sudo podman system prune -a --volumes -f" >&2
    echo "           2. Clean package cache:   sudo apt-get clean" >&2
    echo "           3. Expand partition:      sudo armbian-config (System -> Expand filesystem)" >&2
    echo "           4. See docs/TROUBLESHOOTING.md for external storage (USB/microSD) setup" >&2
  fi
}

# require_supported_arch: exits with a clear message if ARCH is not one we
# expect to work. Called by install.sh after detect_arch.
require_supported_arch() {
  case "$ARCH" in
    aarch64|x86_64)
      return 0
      ;;
    armv7)
      echo "WARNING: armv7 detected. Both hermes-agent and 9router publish" >&2
      echo "         aarch64/x86_64 images; armv7 support is unverified by" >&2
      echo "         this installer (see docs/RESEARCH_NOTES.md). Continuing" >&2
      echo "         anyway, but expect possible image pull failures." >&2
      return 0
      ;;
    *)
      echo "ERROR: unsupported or undetected architecture ($(uname -m))." >&2
      echo "       This installer targets aarch64 (most STB/Armbian devices)" >&2
      echo "       or x86_64. Refusing to continue." >&2
      return 1
      ;;
  esac
}
