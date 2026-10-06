#!/usr/bin/env bash
# lib/swap.sh — automatic swapfile creation for low-RAM STB devices.
# Meant to be sourced by install.sh, not executed directly.
# Requires detect_ram_mb (lib/detect.sh) to have been called first.

SWAP_FILE_PATH="${SWAP_FILE_PATH:-/swapfile-hermes9router}"

# swap_is_active: returns 0 if any swap is already configured on the system.
swap_is_active() {
  [ -s /proc/swaps ] && [ "$(wc -l < /proc/swaps)" -gt 1 ]
}

# swap_recommended_mb: rough sizing — matches RAM up to a 2GB cap, since STB
# storage (often eMMC/SD) is usually also limited. Not scientific, just a
# safe-ish default; override by editing SWAP_SIZE_MB before calling
# ensure_swap.
swap_recommended_mb() {
  local ram="$1"
  local rec=$ram
  [ "$rec" -gt 2048 ] && rec=2048
  [ "$rec" -lt 512 ] && rec=512
  echo "$rec"
}

# ensure_swap RAM_TOTAL_MB THRESHOLD_MB: creates a swapfile if RAM is below
# THRESHOLD_MB and no swap is currently active. No-op otherwise. Respects
# NO_SWAP=1 to skip entirely (set by install.sh's --no-swap flag).
ensure_swap() {
  local ram="$1"
  local threshold="$2"

  if [ "${NO_SWAP:-0}" = "1" ]; then
    echo "  Swap: skipped (--no-swap given)"
    return 0
  fi

  if [ "$ram" -ge "$threshold" ]; then
    echo "  Swap: not needed (${ram}MB RAM >= ${threshold}MB threshold)"
    return 0
  fi

  if swap_is_active; then
    echo "  Swap: already active on this system, leaving as-is"
    return 0
  fi

  local size_mb
  size_mb="$(swap_recommended_mb "$ram")"

  echo "  Swap: RAM (${ram}MB) is below threshold (${threshold}MB)."
  echo "        Creating a ${size_mb}MB swapfile at ${SWAP_FILE_PATH}..."

  if ! command -v fallocate >/dev/null 2>&1; then
    dd if=/dev/zero of="$SWAP_FILE_PATH" bs=1M count="$size_mb" status=none
  else
    fallocate -l "${size_mb}M" "$SWAP_FILE_PATH" || \
      dd if=/dev/zero of="$SWAP_FILE_PATH" bs=1M count="$size_mb" status=none
  fi

  chmod 600 "$SWAP_FILE_PATH"
  mkswap "$SWAP_FILE_PATH" >/dev/null
  swapon "$SWAP_FILE_PATH"

  if ! grep -q "$SWAP_FILE_PATH" /etc/fstab 2>/dev/null; then
    echo "$SWAP_FILE_PATH none swap sw 0 0" >> /etc/fstab
  fi

  echo "  Swap: active (${size_mb}MB)"
}

# remove_swap: reverses ensure_swap. Called by uninstall.sh, only if the
# swapfile at SWAP_FILE_PATH was the one this installer created (fstab entry
# with the same path is used as the signal).
remove_swap() {
  if [ ! -f "$SWAP_FILE_PATH" ]; then
    return 0
  fi
  if ! grep -q "$SWAP_FILE_PATH" /etc/fstab 2>/dev/null; then
    echo "  Swap: ${SWAP_FILE_PATH} exists but wasn't recorded in fstab by this installer — leaving it alone"
    return 0
  fi
  echo "  Swap: removing ${SWAP_FILE_PATH}"
  swapoff "$SWAP_FILE_PATH" 2>/dev/null || true
  sed -i "\|$SWAP_FILE_PATH|d" /etc/fstab
  rm -f "$SWAP_FILE_PATH"
}
