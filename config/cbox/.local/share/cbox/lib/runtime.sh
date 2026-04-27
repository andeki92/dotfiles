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

# Host address the container should use to reach the host's loopback. Differs
# by engine because apple/container 0.11 does NOT inject host.containers.internal
# (or host.docker.internal) into the VM's resolver — but podman does.
#
# For apple/container: the vmnet gateway is the host. The default subnet is
# 192.168.64.0/24 with gateway .1; check `/etc/resolv.conf` inside the VM,
# whose first nameserver line is the gateway.
cbox::runtime_proxy_host() {
  case "$(cbox::engine_name)" in
    container) printf '%s\n' '192.168.64.1' ;;
    podman)    printf '%s\n' 'host.containers.internal' ;;
    *)         printf '%s\n' 'host.containers.internal' ;;
  esac
}

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
  # Resolve to canonical real path. apple/container 0.11 silently no-ops
  # bind mounts whose source traverses a macOS symlink (e.g. /tmp →
  # /private/tmp), leaving /workspace empty inside the container.
  # See https://github.com/apple/containerization/issues/256.
  local real_worktree
  real_worktree=$(cd "$worktree" 2>/dev/null && pwd -P) || real_worktree="$worktree"
  printf '%s\n' -v "${real_worktree}:/workspace:rw"

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

  # Claude auth — forwarded as env var, never as a mount.
  #
  # Anthropic explicitly warns that mounting host ~/.claude into a
  # --dangerously-skip-permissions container exposes credentials. Their
  # devcontainer reference uses a separate volume; their headless guide
  # recommends `claude setup-token` → CLAUDE_CODE_OAUTH_TOKEN env var.
  # We adopt the env-var approach so cbox sessions are stateless w.r.t.
  # auth: no first-run wizard, no theme picker, no host-config tampering
  # surface.
  #
  # Precedence (matches Anthropic's documented auth precedence):
  #   1. CLAUDE_CODE_OAUTH_TOKEN from ~/.cbox/oauth-token (mode 600)
  #   2. CLAUDE_CODE_OAUTH_TOKEN from host env
  #   3. ANTHROPIC_API_KEY from host env
  # If none are set, the container will land in Claude's first-run flow
  # — `cbox doctor` warns about this earlier.
  local _cbox_token_file="$(cbox::home)/oauth-token"
  if [[ -f "$_cbox_token_file" ]]; then
    local _tok
    _tok=$(< "$_cbox_token_file")
    [[ -n "$_tok" ]] && printf '%s\n' -e "CLAUDE_CODE_OAUTH_TOKEN=${_tok}"
  elif [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    printf '%s\n' -e "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}"
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    printf '%s\n' -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
  fi

  # Claude plugins — directory bind-mount (read-only) so the agent can
  # USE installed plugins (rust-skills, superpowers, etc.) but cannot
  # install new ones, modify the host plugin set, or read other ~/.claude
  # state (credentials, projects, conversation history). Plugin code is
  # code the agent could already write; the security boundary that matters
  # is the writable scope, not the readable scope.
  #
  # We do NOT mount ~/.claude/settings.json. Single-file bind mounts are
  # silently dropped by apple/container 0.11, AND the host's settings.json
  # leaks per-project Bash permission allowlists into every session. The
  # entrypoint synthesizes a fresh settings.json from the host's plugin
  # keys (forwarded via CBOX_HOST_CLAUDE_SETTINGS env) instead.
  if [[ -d "$HOME/.claude/plugins" ]]; then
    printf '%s\n' -v "$HOME/.claude/plugins:/home/agent/.claude/plugins:ro"
  fi
  if [[ -f "$HOME/.claude/settings.json" ]] && command -v jq >/dev/null 2>&1; then
    # Extract only plugin-relevant keys (drop permissions, voice, project
    # state, etc.). Pass to the container as a single-line JSON env var
    # for the entrypoint to merge into the synthesized settings.json.
    local _claude_settings
    _claude_settings=$(jq -c '{enabledPlugins, extraKnownMarketplaces, installedPlugins} | with_entries(select(.value != null))' "$HOME/.claude/settings.json" 2>/dev/null || printf '{}')
    printf '%s\n' -e "CBOX_HOST_CLAUDE_SETTINGS=${_claude_settings}"
  fi

  # Host package caches — DISABLED by default. The 2025-2026 npm/PyPI worm
  # campaigns actively poison these dirs (planting binaries that the host's
  # next `cargo install` / `npm i` runs as the user). A single bad transitive
  # dep installed inside cbox = host pwn.
  #
  # Opt back in with CBOX_SHARE_HOST_CACHES=1 if you accept the trade — the
  # speedup of warm caches vs. the supply-chain risk. The agent won't have
  # offline-installed-toolchains by default; first-session `mise install` runs
  # against the network, gated by Squid.
  if [[ "${CBOX_SHARE_HOST_CACHES:-0}" == "1" ]]; then
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
  fi

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
