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

# print_detect_summary: human-readable summary of everything detected above.
# Call detect_arch / detect_ram_mb / detect_distro first.
print_detect_summary() {
  echo "  Architecture : ${ARCH:-unknown} (raw: $(uname -m))"
  echo "  Total RAM    : ${RAM_TOTAL_MB:-?} MB"
  echo "  Distro       : ${DISTRO_ID:-unknown} ${DISTRO_VERSION:-}"
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
