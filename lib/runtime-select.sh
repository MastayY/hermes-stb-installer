#!/usr/bin/env bash
# lib/runtime-select.sh — pick and install the container runtime.
# Meant to be sourced by install.sh, not executed directly.
#
# Default: Podman rootless. Docker rootful is available via --runtime=docker.
# Why Podman is the default (daemonless + rootless networking doesn't touch host iptables/UFW).

RUNTIME_STATE_FILE="${RUNTIME_STATE_FILE:-.runtime}"

# select_runtime NAME: validates NAME (podman|docker), installs it if
# missing, and persists the choice to RUNTIME_STATE_FILE for
# uninstall.sh/update.sh to read later. Sets CONTAINER_RUNTIME.
select_runtime() {
  local requested="${1:-podman}"

  case "$requested" in
    podman|docker) : ;;
    *)
      echo "ERROR: unknown runtime '$requested' (expected 'podman' or 'docker')" >&2
      return 1
      ;;
  esac

  CONTAINER_RUNTIME="$requested"
  export CONTAINER_RUNTIME

  if ! command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1; then
    echo "  Runtime: $CONTAINER_RUNTIME not found, installing..."
    if [ "$CONTAINER_RUNTIME" = "podman" ]; then
      install_podman
    else
      install_docker
    fi
  else
    echo "  Runtime: $CONTAINER_RUNTIME already installed ($($CONTAINER_RUNTIME --version 2>/dev/null | head -1))"
  fi

  # Verify compose tool is available under either invocation style.
  if ! resolve_compose_command "$CONTAINER_RUNTIME"; then
    echo "ERROR: compose tool is not available for '$CONTAINER_RUNTIME'." >&2
    echo "       This installer needs either '$CONTAINER_RUNTIME compose' (Podman 4.7+)" >&2
    echo "       or an external compose binary ('podman-compose' / 'docker-compose')." >&2
    return 1
  fi
  echo "  Runtime: using compose command '${COMPOSE_CMD[*]}'"

  echo "$CONTAINER_RUNTIME" > "$RUNTIME_STATE_FILE"
}

# resolve_compose_command: determines the right compose command to use.
# For Podman: checks "podman compose" (Podman >= 4.7), then fallbacks to "podman-compose" (Debian 12 / Podman 4.3).
# For Docker: checks "docker compose" (docker-compose-plugin), then fallbacks to "docker-compose".
resolve_compose_command() {
  local runtime="${1:-${CONTAINER_RUNTIME:-podman}}"

  if [ "$runtime" = "podman" ]; then
    if podman compose version >/dev/null 2>&1; then
      COMPOSE_CMD=("podman" "compose")
      return 0
    elif command -v podman-compose >/dev/null 2>&1; then
      COMPOSE_CMD=("podman-compose")
      return 0
    fi
  elif [ "$runtime" = "docker" ]; then
    if docker compose version >/dev/null 2>&1; then
      COMPOSE_CMD=("docker" "compose")
      return 0
    elif command -v docker-compose >/dev/null 2>&1; then
      COMPOSE_CMD=("docker-compose")
      return 0
    fi
  fi

  return 1
}

install_podman() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq || echo "  apt-get update reported errors, trying install anyway" >&2
    apt-get install -y podman podman-compose uidmap slirp4netns
  else
    echo "ERROR: no apt-get found. This installer's automatic Podman install" >&2
    echo "       only supports Debian/Armbian-family systems currently." >&2
    echo "       Install podman manually and re-run." >&2
    return 1
  fi
}

install_docker() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq || echo "  apt-get update reported errors, trying install anyway" >&2
    apt-get install -y docker.io docker-compose-plugin
  else
    echo "ERROR: no apt-get found. Install Docker manually (see" >&2
    echo "       https://docs.docker.com/engine/install/) and re-run." >&2
    return 1
  fi
}

# compose_files: echoes the -f arguments to pass to `compose`, based on
# whether --with-proxy was requested (WITH_PROXY=1) and HERMES_MODE.
compose_files() {
  local files="-f compose/docker-compose.yml"
  if [ "${WITH_PROXY:-0}" = "1" ]; then
    files="$files -f compose/docker-compose.proxy.yml"
  fi
  echo "$files"
}

# compose ARGS...: runs `<compose_command> <compose_files> ARGS...`
compose() {
  if [ -z "${COMPOSE_CMD+x}" ] || [ "${#COMPOSE_CMD[@]}" -eq 0 ]; then
    resolve_compose_command "${CONTAINER_RUNTIME:-podman}" || {
      echo "ERROR: compose command is not available for '${CONTAINER_RUNTIME:-podman}'." >&2
      return 1
    }
  fi
  # shellcheck disable=SC2046
  "${COMPOSE_CMD[@]}" $(compose_files) "$@"
}

# smoke_test_runtime: the "does this actually work" check — not just a
# version check. Kernel/cgroups on some Armbian STB builds are stripped
# down enough that a real container run fails even though the CLI reports
# a version fine.
smoke_test_runtime() {
  echo "  Runtime: running smoke test (hello-world container)..."
  if "$CONTAINER_RUNTIME" run --rm hello-world >/dev/null 2>&1; then
    echo "  Runtime: smoke test passed"
    return 0
  fi
  echo "ERROR: '$CONTAINER_RUNTIME run --rm hello-world' failed." >&2
  echo "       This usually means the kernel is missing cgroups/overlayfs" >&2
  echo "       support needed by containers — common on stripped-down" >&2
  echo "       Armbian builds for STB hardware. Check:" >&2
  echo "       - cat /proc/cgroups   (need cpu, memory, pids controllers)" >&2
  echo "       - lsmod | grep overlay" >&2
  echo "       See docs/TROUBLESHOOTING.md." >&2
  return 1
}
