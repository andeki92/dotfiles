# cbox engine — abstracts apple/container (macOS) vs rootful podman (Linux).
#
# Architectural note: cbox uses a long-lived container per session that does
# nothing but `sleep infinity`. The user-facing TUI (claude) is launched via
# `engine_exec -i -t` from inside a tmux pane that already has a real PTY.
# Apple's `container` 0.11 returns "Operation not supported by device" when
# given -i + -t at run-time if stdin isn't a tty (which it isn't under
# `tmux new-session -d`), so we cannot make Claude the entrypoint directly.
# `container exec -it` from within an attached tmux pane works correctly.
# See: https://github.com/apple/container/issues/378
#
# Functions exported to callers (runtime.sh, session.sh, doctor.sh):
#
#   cbox::engine_name             → "container" or "podman" (string)
#   cbox::engine_cli              → bare CLI binary name (alias of engine_name)
#   cbox::engine_ready            → 0 if engine usable; logs+nonzero otherwise
#   cbox::engine_build IMAGE CONTEXT_DIR
#   cbox::engine_image_exists IMAGE
#   cbox::engine_run_detached <args...> IMAGE
#                                 → start a long-lived container in background
#                                   (no -i, no -t — caller's args + image)
#   cbox::engine_exec_tty NAME <cmd...>
#                                 → exec interactively into running container
#                                   (-i -t for the TUI; tmux pane gives PTY)
#   cbox::engine_stop NAME        → graceful stop then remove
#   cbox::engine_rm NAME          → force-remove (use when graceful failed)
#
# Image tag is "cbox:latest" (no registry prefix); both engines understand it.

cbox::engine_name() {
  case "$(uname -s)" in
    Darwin) printf 'container\n' ;;
    Linux)  printf 'podman\n' ;;
    *)      cbox::log_err "unsupported OS: $(uname -s)"; return 1 ;;
  esac
}

cbox::engine_cli() {
  local n; n=$(cbox::engine_name) || return 1
  printf '%s\n' "$n"
}

cbox::engine_ready() {
  local cli; cli=$(cbox::engine_cli) || return 1
  cbox::require_cmd "$cli" || return 1
  case "$cli" in
    container)
      # apple/container needs the system service running.
      if ! container system status >/dev/null 2>&1; then
        cbox::log_err "apple/container system not running. Run: container system start"
        return 1
      fi
      ;;
    podman)
      podman info >/dev/null 2>&1 || {
        cbox::log_err "podman not ready. On Linux, ensure rootful podman is installed."
        return 1
      }
      ;;
  esac
}

cbox::engine_build() {
  local image="${1:?image}" ctx="${2:?context}"
  local cli; cli=$(cbox::engine_cli) || return 1
  # apple/container's `build` rejects symlinked context dirs (it lstat()s
  # the path rather than following it). Resolve to the canonical real path
  # so a Stow-managed ~/.config/cbox works the same as a literal dir.
  local real_ctx
  real_ctx=$(cd "$ctx" 2>/dev/null && pwd -P) || {
    cbox::log_err "build context not accessible: $ctx"; return 1; }
  cbox::log "building $image via $cli (context: $real_ctx)"
  "$cli" build -t "$image" \
    --build-arg "UID=$(id -u)" --build-arg "GID=$(id -g)" \
    "$real_ctx"
}

cbox::engine_image_exists() {
  local image="${1:?image}"
  local cli; cli=$(cbox::engine_cli) || return 1
  case "$cli" in
    container)
      container image list --quiet 2>/dev/null | grep -qx "$image"
      ;;
    podman)
      podman image exists "$image"
      ;;
  esac
}

cbox::engine_run_detached() {
  # Start a container in the background with the caller-provided args
  # (mounts, env, --name, etc.). The image's CMD ("sleep infinity") keeps
  # it alive. Returns 0 on success.
  #
  # Important: NO -i / -t here. Detached + interactive flags collide on
  # apple/container ("Operation not supported by device").
  local cli; cli=$(cbox::engine_cli) || return 1
  "$cli" run -d "$@"
}

cbox::engine_exec_tty() {
  # exec a command inside a running container with a real interactive TTY.
  # Caller invokes this from a tmux pane (which provides the PTY).
  # `exec` here = bash exec (replace cbox shell), so the user gets the
  # container's stdin/stdout directly inside their tmux pane.
  local name="${1:?name}"; shift
  local cli; cli=$(cbox::engine_cli) || return 1
  exec "$cli" exec -i -t "$name" "$@"
}

cbox::engine_stop() {
  # Graceful stop then remove. Apple/container's `stop` accepts a timeout
  # via --signal/--timeout; podman uses --time. We rely on default 10s for
  # both, which is plenty for `sleep infinity`.
  local name="${1:?name}"
  local cli; cli=$(cbox::engine_cli) || return 1
  "$cli" stop "$name" 2>/dev/null || true
  "$cli" rm "$name" 2>/dev/null || true
}

cbox::engine_rm() {
  # Force-remove (used as a fallback / for cleanup of stopped containers).
  local name="${1:?name}"
  local cli; cli=$(cbox::engine_cli) || return 1
  case "$cli" in
    container) "$cli" rm "$name" 2>/dev/null || true ;;
    podman)    "$cli" rm -f "$name" 2>/dev/null || true ;;
  esac
}
