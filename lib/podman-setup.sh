#!/usr/bin/env bash
# lib/podman-setup.sh — rootless Podman auto-start setup.
# Meant to be sourced by install.sh, not executed directly. Only called
# when CONTAINER_RUNTIME=podman.
#
# Confidence note: the `loginctl enable-linger` step is well-established
# and was cross-checked via web search during planning. The
# `podman-restart.service` unit name is Podman's own documented mechanism
# for restarting containers with a restart policy after boot/reboot, but
# its exact availability/name can vary by Podman version and distro
# packaging — verify with `systemctl --user list-unit-files | grep podman`
# after install and adjust here if it's named differently on your target
# distro.

setup_podman_rootless_autostart() {
  local target_user="${SUDO_USER:-$USER}"

  # Confirmed via hands-on testing during development
  # rootless Podman needs subuid/subgid ranges for
  # the target user. `useradd -m` provisions these automatically on some
  # distros but not reliably on all Armbian builds — check and fix rather
  # than assume.
  if ! grep -q "^${target_user}:" /etc/subuid 2>/dev/null; then
    echo "  Podman: no /etc/subuid entry for '$target_user', adding one..."
    echo "${target_user}:100000:65536" >> /etc/subuid
  fi
  if ! grep -q "^${target_user}:" /etc/subgid 2>/dev/null; then
    echo "  Podman: no /etc/subgid entry for '$target_user', adding one..."
    echo "${target_user}:100000:65536" >> /etc/subgid
  fi

  echo "  Podman: enabling lingering for user '$target_user' (keeps rootless"
  echo "          containers running after logout / across reboot)..."
  loginctl enable-linger "$target_user" 2>/dev/null || {
    echo "WARNING: 'loginctl enable-linger' failed. Rootless containers will" >&2
    echo "         only stay up while $target_user has an active session." >&2
  }

  echo "  Podman: enabling podman-restart.service for boot-time auto-restart..."
  if su - "$target_user" -c 'systemctl --user list-unit-files podman-restart.service' >/dev/null 2>&1; then
    su - "$target_user" -c 'systemctl --user enable --now podman-restart.service' \
      || echo "WARNING: could not enable podman-restart.service — verify manually." >&2
  else
    echo "WARNING: podman-restart.service not found for user '$target_user'." >&2
    echo "         Your Podman version/packaging may name or provide this" >&2
    echo "         differently. Containers started with 'restart: unless-stopped'" >&2
    echo "         will still restart on failure while the session is active," >&2
    echo "         but may not survive a full host reboot without this unit." >&2
    echo "         See docs/TROUBLESHOOTING.md." >&2
  fi
}

# teardown_podman_rootless_autostart: reverses the above, called by uninstall.sh
teardown_podman_rootless_autostart() {
  local target_user="${SUDO_USER:-$USER}"
  su - "$target_user" -c 'systemctl --user disable --now podman-restart.service' 2>/dev/null || true
  # Deliberately NOT calling `loginctl disable-linger` here — the user may
  # have enabled lingering for other reasons unrelated to this installer.
}
