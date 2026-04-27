# cbox runtime — pure builder for the engine `run -d` argv.
#
# Sourced by lib/session.sh. No side effects beyond reading the host
# environment (existence of files/sockets). Prints one argv element per
# line on stdout; the image tag is always the LAST line.
#
# Caller pattern (session.sh):
#   mapfile -t engine_args < <(cbox::runtime_args "$wt" "$id" "$name" "$mounts")
#   cbox::engine_run_detached "${engine_args[@]}"
#
# The container CMD is `sleep infinity` (set in the Containerfile) — keeps
# the container alive so cbox can `exec` into it from a tmux pane that owns
# a real PTY. The user-facing TUI (claude) is launched via engine_exec_tty.
#
# We deliberately do NOT pass -i or -t in this argv. -d (detached) is added
# by engine_run_detached itself; -i + -t collide with -d on apple/container
# 0.11 ("Operation not supported by device"). Interactivity comes from the
# subsequent `container exec -it`.
#
# The image tag defaults to "cbox:latest"; override with $CBOX_IMAGE.

# Hostname apple/container exposes for host-loopback services. Podman uses
# the same name when configured, so a single constant suffices for v2.
cbox::runtime_proxy_host() { printf '%s\n' 'host.containers.internal'; }

# cbox::runtime_args <worktree_dir> <id> <session_name> <extra_mounts_json>
#
# Emits the full engine `run` argv on stdout, one element per line, image
# tag last. Extra mounts JSON should be a (possibly empty) JSON array of
# strings of the form "src:dst[:flags]" — passed verbatim to `-v`.
cbox::runtime_args() {
  local worktree="${1:?cbox::runtime_args requires a worktree dir}"
  local id="${2:?cbox::runtime_args requires an id}"
  local session_name="${3:?cbox::runtime_args requires a session name}"
  local extra_mounts="${4:-[]}"

  local proxy_host proxy_port image
  proxy_host=$(cbox::runtime_proxy_host)
  proxy_port=3128
  image="${CBOX_IMAGE:-cbox:latest}"

  # Core flags ----------------------------------------------------------------
  # No -i / -t — see file header. -d is added by engine_run_detached.
  # No --rm either: we destroy the container explicitly via engine_stop on
  # session_rm, so the user can `cbox up` after a tmux detach without losing
  # any in-container state (caches, package installs, running processes).
  # apple/container 0.11 has no --hostname; the in-container hostname is
  # auto-set to --name, which is good enough for our purposes.
  printf '%s\n' --name "$session_name"

  # Proxy + identity env ------------------------------------------------------
  printf '%s\n' -e "HTTPS_PROXY=http://${proxy_host}:${proxy_port}"
  printf '%s\n' -e "HTTP_PROXY=http://${proxy_host}:${proxy_port}"
  printf '%s\n' -e "NO_PROXY=localhost,127.0.0.1"
  printf '%s\n' -e "CBOX_INSIDE=1"
  printf '%s\n' -e "CBOX_SESSION_ID=${id}"
  printf '%s\n' -e "TERM=${TERM:-xterm}"

  # Workspace -----------------------------------------------------------------
  printf '%s\n' -v "${worktree}:/workspace:rw"

  # Optional gitconfig --------------------------------------------------------
  if [[ -f "$HOME/.gitconfig" ]]; then
    printf '%s\n' -v "$HOME/.gitconfig:/home/agent/.gitconfig:ro"
  fi

  # Optional ssh-agent forwarding --------------------------------------------
  if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
    printf '%s\n' -v "${SSH_AUTH_SOCK}:/run/host-services/ssh-agent.sock"
    printf '%s\n' -e "SSH_AUTH_SOCK=/run/host-services/ssh-agent.sock"
  fi

  # Optional gpg-agent forwarding (only if the user actually signs commits).
  # `git config --global --get` exits non-zero on absent keys; swallow that.
  local gpg_signs gpg_socket
  gpg_signs=$(git config --global --get commit.gpgsign 2>/dev/null || true)
  if [[ "$gpg_signs" == "true" ]] && command -v gpgconf >/dev/null 2>&1; then
    gpg_socket=$(gpgconf --list-dir agent-socket 2>/dev/null || true)
    if [[ -n "$gpg_socket" && -S "$gpg_socket" ]]; then
      printf '%s\n' -v "${gpg_socket}:/run/host-services/gpg-agent.sock"
      printf '%s\n' -e "GPG_AGENT_INFO=/run/host-services/gpg-agent.sock"
    fi
  fi

  # Optional ~/.claude (read-only, holds CLI auth + skills).
  if [[ -d "$HOME/.claude" ]]; then
    printf '%s\n' -v "$HOME/.claude:/home/agent/.claude:ro"
  fi

  # Host package caches — only mount the ones that already exist so we don't
  # silently create empty cache dirs the user never asked for.
  local cache
  for cache in \
      "$HOME/.cache/mise" \
      "$HOME/.cache/cargo" \
      "$HOME/.npm" \
      "$HOME/.cache/pip" \
      "$HOME/.cache/go-build"; do
    if [[ -d "$cache" ]]; then
      printf '%s\n' -v "${cache}:${cache}:rw"
    fi
  done

  # Caller-supplied extra mounts (raw "src:dst[:flags]" strings) -------------
  if [[ -n "$extra_mounts" && "$extra_mounts" != "[]" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
      cbox::log_err "jq required to parse extra_mounts JSON"
      return 1
    fi
    local mount
    while IFS= read -r mount; do
      [[ -z "$mount" ]] && continue
      printf '%s\n' -v "$mount"
    done < <(printf '%s' "$extra_mounts" | jq -r '.[]')
  fi

  # Image tag — MUST be last so the caller can append an in-container command
  # by simply concatenating to the array, and so podman/container parse the
  # remainder as `[image] [cmd...]`.
  printf '%s\n' "$image"
}
