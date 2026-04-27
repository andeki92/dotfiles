# cbox engine — abstracts apple/container (macOS) vs rootful podman (Linux).
# Functions exported to callers (runtime.sh, session.sh, doctor.sh):
#
#   cbox::engine_name      → "container" or "podman" (string identifier)
#   cbox::engine_cli       → bare CLI binary name on PATH (alias of engine_name)
#   cbox::engine_build IMAGE CONTEXT_DIR
#   cbox::engine_run [args...] IMAGE
#   cbox::engine_image_exists IMAGE
#   cbox::engine_rm CONTAINER_NAME (force-remove a stopped container; ignored if missing)
#   cbox::engine_ready   (returns 0 if engine is usable; logs+nonzero otherwise)
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

cbox::engine_run() {
  # All args including the image name and the in-container command.
  # Caller is responsible for assembling the full argv (mounts, env, etc.).
  local cli; cli=$(cbox::engine_cli) || return 1
  exec "$cli" run "$@"
}

cbox::engine_rm() {
  local name="${1:?name}"
  local cli; cli=$(cbox::engine_cli) || return 1
  "$cli" rm -f "$name" 2>/dev/null || true
}
