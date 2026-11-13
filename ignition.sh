#!/usr/bin/env bash
#
# ignition.sh - control the Kanoa/Ignition dev stack (podman-compose) and Designer.
#
# Run this on the HOST (not inside the toolbox).
#
# Usage:
#   ignition.sh                      start all containers (podman-compose up -d) and
#                                    wait until the Gateway answers
#   ignition.sh -d                   open Designer Launcher in the toolbox
#                                    (also: --designer, designer)
#   ignition.sh recreate [service]   podman-compose up -d --force-recreate <service>
#                                    (default: kanoa) and wait for the Gateway
#   ignition.sh stop                 podman-compose stop (containers and data are kept)
#   ignition.sh status               podman-compose ps + Gateway state
#   ignition.sh logs [service]       follow logs (default: kanoa)
#
# Where is the compose project? In this order:
#   $IGNITION_COMPOSE_DIR, the folder of this script, the current folder.
#
# Other settings (environment variables):
#   IGNITION_URL (default http://localhost:8088)   IGNITION_WAIT (seconds, default 240)
#   IGNITION_TOOLBOX (default ignition-designer)   IGNITION_LAUNCHER_ROOT (default ~/ignition-designer)
#   IGNITION_LAUNCHER_DIR (exact folder with designerlauncher.sh; skips auto-detection)

set -u

TOOLBOX="${IGNITION_TOOLBOX:-ignition-designer}"
GATEWAY_URL="${IGNITION_URL:-http://localhost:8088}"
LAUNCHER_ROOT="${IGNITION_LAUNCHER_ROOT:-$HOME/ignition-designer}"
WAIT_SECONDS="${IGNITION_WAIT:-240}"
DEFAULT_SERVICE="kanoa"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Print the leading comment block of this file (the help text).
usage() { awk 'NR>=3 && /^#/ {sub(/^# ?/, ""); print; next} NR>=3 {exit}' "$0"; }

has_compose_file() {
  [ -f "$1/docker-compose.yaml" ] || [ -f "$1/docker-compose.yml" ] ||
  [ -f "$1/compose.yaml" ] || [ -f "$1/compose.yml" ]
}

find_compose_dir() {
  local script_dir cand
  script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
  for cand in "${IGNITION_COMPOSE_DIR:-}" "$script_dir" "$PWD"; do
    [ -n "$cand" ] && has_compose_file "$cand" && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}

check_host() {
  if [ -e /run/.toolboxenv ]; then
    die "You are inside a toolbox. Run 'exit' first and start this script on the host."
  fi
  command -v podman-compose >/dev/null 2>&1 || die "podman-compose not found."
  command -v toolbox        >/dev/null 2>&1 || die "toolbox not found."
  command -v curl           >/dev/null 2>&1 || die "curl not found."
}

enter_compose_dir() {
  local dir
  dir="$(find_compose_dir)" \
    || die "No compose file found. Put this script into the kanoa-docker-template folder or set IGNITION_COMPOSE_DIR=/path/to/it"
  cd "$dir" || die "Cannot cd to $dir"
  info "Compose project: $dir"
}

gateway_up() {
  curl -fs --max-time 3 "$GATEWAY_URL/StatusPing" 2>/dev/null | grep -q RUNNING
}

# Not fatal: with a Traefik hostname instead of localhost:8088 the check would never
# succeed, and the containers are still up.
wait_gateway() {
  info "Waiting for the Gateway at $GATEWAY_URL (up to ${WAIT_SECONDS}s)..."
  local waited=0
  until gateway_up; do
    if [ "$waited" -ge "$WAIT_SECONDS" ]; then
      printf '\n'
      warn "Gateway did not answer at $GATEWAY_URL in ${WAIT_SECONDS}s (wrong URL? set IGNITION_URL)."
      return 1
    fi
    printf '.'
    sleep 3
    waited=$((waited + 3))
  done
  [ "$waited" -gt 0 ] && printf '\n'
  info "Gateway is running: $GATEWAY_URL"
}

# The archive can unpack into nested folders, so several designerlauncher.sh may exist.
# Pick the real launcher: the one that has its bundled Java and jar next to it.
find_launcher_dir() {
  if [ -n "${IGNITION_LAUNCHER_DIR:-}" ]; then
    printf '%s\n' "$IGNITION_LAUNCHER_DIR"
    return 0
  fi
  local script first=""
  while IFS= read -r script; do
    [ -n "$first" ] || first="$script"
    if [ -x "$(dirname "$script")/runtime/bin/java" ] && [ -f "$(dirname "$script")/app/launcher-designer-linux.jar" ]; then
      dirname "$script"
      return 0
    fi
  done < <(find "$LAUNCHER_ROOT" -name designerlauncher.sh -type f 2>/dev/null)
  [ -n "$first" ] || return 1
  warn "No designerlauncher.sh with runtime/ and app/ found; using $first"
  dirname "$first"
}

launch_designer() {
  toolbox list --containers 2>/dev/null | grep -qw -- "$TOOLBOX" \
    || die "Toolbox '$TOOLBOX' does not exist."

  local dir
  dir="$(find_launcher_dir)" \
    || die "designerlauncher.sh not found under $LAUNCHER_ROOT."

  info "Opening Designer Launcher from $dir (close its window to return here)..."
  toolbox run --container "$TOOLBOX" bash -c '
    cd "$1" || exit 1
    exec env -u WAYLAND_DISPLAY mesa_glthread=false _JAVA_AWT_WM_NONREPARENTING=1 \
      JAVA_TOOL_OPTIONS="-Dawt.robot.screenshotMethod=x11 -Dsun.java2d.xrender=false" \
      ./designerlauncher.sh
  ' _ "$dir" 2>&1 | cat
  # Observed on Fedora KDE: with output going straight to the terminal the launcher
  # window never appears; with output piped (as here) it opens normally.
  local rc="${PIPESTATUS[0]}"
  if [ "$rc" -ne 0 ]; then
    warn "Designer Launcher exited with code $rc. Run it by hand in the toolbox to see the error."
  fi
}

main() {
  local cmd="${1:-start}"
  case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
  esac

  check_host

  case "$cmd" in
    start)
      enter_compose_dir
      info "podman-compose up -d"
      podman-compose up -d || die "podman-compose up failed."
      wait_gateway
      ;;
    -d|--designer|designer)
      gateway_up || warn "Gateway is not answering at $GATEWAY_URL; start the containers first with: ${0##*/}"
      launch_designer
      ;;
    recreate)
      shift
      [ "$#" -gt 0 ] || set -- "$DEFAULT_SERVICE"
      enter_compose_dir
      info "podman-compose up -d --force-recreate $*"
      podman-compose up -d --force-recreate "$@" || die "podman-compose up failed."
      wait_gateway
      ;;
    stop)
      enter_compose_dir
      info "podman-compose stop (containers and data are kept)"
      podman-compose stop || die "podman-compose stop failed."
      info "Stopped. If Designer is still open, close it too."
      ;;
    status)
      enter_compose_dir
      podman-compose ps
      echo
      if gateway_up; then info "Gateway: RUNNING ($GATEWAY_URL)"; else warn "Gateway: not answering at $GATEWAY_URL"; fi
      ;;
    logs)
      shift
      [ "$#" -gt 0 ] || set -- "$DEFAULT_SERVICE"
      enter_compose_dir
      podman-compose logs -f "$@"
      ;;
    *)
      usage; exit 1 ;;
  esac
}

main "$@"
