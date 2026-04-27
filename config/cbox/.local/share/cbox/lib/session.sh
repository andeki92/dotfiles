# cbox session — lifecycle commands invoked by bin/cbox.
#
# Each function maps 1:1 to a top-level CLI verb (`cbox`, `cbox attach`,
# `cbox stop`, `cbox up`, `cbox rm`, `cbox ls`, `cbox prune`). The common
# sub-pieces — engine argv assembly (runtime.sh), state mutations
# (state.sh), and proxy refcount lifecycle (proxy.sh) — are intentionally
# orchestrated here so the dispatcher in bin/cbox stays a thin shim.
#
# Refcount safety: state mutations happen inside flock-protected helpers
# (cbox::state_add / cbox::state_remove). Proxy ensure/stop are called
# outside the lock but consult `cbox::state_list`, so two concurrent
# `cbox` invocations serialize their state writes and only one observes
# the count==0 transition on shutdown.

# TODO V2-9: wire config + secrets. Until then we use empty defaults:
#   - extra_mounts='[]' (no project-specific bind mounts)
#   - env_args=()       (no --env-file=... lines from secrets.sh)

# ---- internal helpers ---------------------------------------------------------

# Assemble the runtime argv for a session. Returns the array via the named
# global `_CBOX_ENGINE_ARGS` because bash can't return arrays cleanly.
cbox::_session_build_engine_args() {
  local worktree="${1:?worktree}" id="${2:?id}" name="${3:?name}"
  local extra_mounts='[]'  # TODO V2-9: from cbox::config_load
  _CBOX_ENGINE_ARGS=()
  local line
  while IFS= read -r line; do
    _CBOX_ENGINE_ARGS+=("$line")
  done < <(cbox::runtime_args "$worktree" "$id" "$name" "$extra_mounts")
}

# Start the long-lived container in the background, then spawn a detached
# tmux session whose pane runs `engine exec -it <name> entrypoint <cmd>`.
# The exec call (run from a tmux pane that owns a real PTY) is what gives
# Claude the interactive terminal it needs — see the engine.sh header for
# why we can't make claude the entrypoint directly.
cbox::_session_spawn_tmux() {
  local tmux_session="${1:?tmux session}" worktree="${2:?worktree}"
  shift 2
  local -a engine_args=("$@")
  # Container name === tmux session name (set by runtime_args via --name).
  local container_name="$tmux_session"

  cbox::require_cmd tmux || return 1
  local cli; cli=$(cbox::engine_cli) || return 1

  # Start the container detached if it isn't already. (session_up calls us
  # against an existing-but-not-attached container; first-time session_new
  # calls us with no prior container.) The image's CMD ("sleep infinity")
  # keeps it alive until session_stop / session_rm tear it down explicitly.
  #
  # NB: apple/container's `inspect` returns 0 with `[]` even for unknown
  # IDs — exit-code-only check would always claim "exists". Match the
  # actual ID via `list -a --quiet` instead.
  if "$cli" list -a --quiet 2>/dev/null | grep -qx "$container_name"; then
    cbox::log "reusing existing container ${container_name}"
  else
    if ! cbox::engine_run_detached "${engine_args[@]}"; then
      cbox::log_err "failed to start container ${container_name}"
      return 1
    fi
  fi

  # Build the in-pane command: exec into the running container with -i -t,
  # invoke the entrypoint (mise install + exec) — but wrap the final claude
  # command in script(1) to forge a fresh PTY pair around it.
  #
  # apple/container's `exec -i -t` reports stdin as a TTY to the immediate
  # child but Node's process.stdin.isTTY check returns false for processes
  # started further down the chain, which makes Claude Code 2.x flip into
  # `--print` mode and exit with "Input must be provided…". The standard
  # workaround (per anthropics/claude-code#34430) is `script -qc <cmd> /dev/null`,
  # which synthesizes a clean PTY pair satisfying isTTY for the wrapped process.
  local inner_cmd
  printf -v inner_cmd 'script -qc %s /dev/null' \
    "$(printf '%q' 'claude --dangerously-skip-permissions')"
  local cmd
  printf -v cmd '%s exec -i -t %s /usr/local/bin/entrypoint.sh %s %s' \
    "$cli" \
    "$(printf '%q' "$container_name")" \
    "$(printf '%q' '/bin/bash')" \
    "$(printf '%q' "-c") $(printf '%q' "$inner_cmd")"

  if ! tmux new-session -d -s "$tmux_session" -c "$worktree" "$cmd"; then
    cbox::log_err "tmux new-session failed"
    cbox::engine_stop "$container_name"
    return 1
  fi
}

# Returns 0 if a tmux session with the given name exists.
cbox::_session_tmux_alive() {
  local name="${1:?name}"
  command -v tmux >/dev/null 2>&1 || return 1
  tmux has-session -t "$name" 2>/dev/null
}

# Resolve a session id from (a) an explicit arg or (b) an interactive
# fzf picker over the state list. Echoes the id on stdout.
cbox::_session_resolve_or_pick() {
  local query="${1:-}"
  if [[ -n "$query" ]]; then
    cbox::state_resolve_id "$query"
    return $?
  fi
  cbox::session_pick
}

# Remove the worktree directory and prune git's bookkeeping. Best-effort:
# falls back to `rm -rf` if the worktree dir is no longer registered.
cbox::_session_remove_worktree() {
  local repo="${1:?repo}" worktree="${2:?worktree}"
  if [[ -d "$repo/.git" || -f "$repo/.git" ]]; then
    git -C "$repo" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
    git -C "$repo" worktree prune 2>/dev/null || true
  else
    rm -rf "$worktree"
  fi
}

# Best-effort branch deletion: only delete local branches with no upstream
# (i.e. unpublished work). Branches with an upstream are left alone so
# the user keeps a remote ref for archeology.
cbox::_session_maybe_delete_branch() {
  local repo="${1:?repo}" branch="${2:?branch}"
  [[ -d "$repo/.git" || -f "$repo/.git" ]] || return 0
  if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "${branch}@{u}" \
       >/dev/null 2>&1; then
    return 0   # has upstream — leave it alone
  fi
  git -C "$repo" branch -D "$branch" 2>/dev/null || true
}

# Returns 0 if the branch has no commits ahead of its upstream (or has
# no upstream at all and no commits beyond the merge-base — i.e. nothing
# that would be lost). Returns 1 if there are unpushed commits.
cbox::_session_branch_is_safe_to_remove() {
  local repo="${1:?repo}" branch="${2:?branch}"
  [[ -d "$repo/.git" || -f "$repo/.git" ]] || return 0
  local upstream ahead
  if upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name \
                  "${branch}@{u}" 2>/dev/null); then
    ahead=$(git -C "$repo" rev-list --count "${upstream}..${branch}" 2>/dev/null || echo 0)
    [[ "${ahead:-0}" -eq 0 ]]
  else
    # No upstream: any commits past HEAD's parent count as unpublished.
    # Conservative: if the branch has commits not reachable from any other
    # local branch, treat as unsafe.
    local merged
    merged=$(git -C "$repo" branch --merged "$branch" 2>/dev/null \
              | grep -v -E "^\*?\s*${branch}\$" | head -n1 || true)
    [[ -n "$merged" ]]
  fi
}

# ---- public API ---------------------------------------------------------------

# cbox::session_new <repo_root>
#
# Main "cbox" command. Creates a worktree on a fresh branch off HEAD,
# records state, ensures the proxy is up, then attaches via tmux.
cbox::session_new() {
  local repo="${1:?cbox::session_new requires a repo path}"

  if [[ "${CBOX_INSIDE:-0}" == "1" ]]; then
    cbox::log_err "refusing to nest: already inside a cbox session"
    return 1
  fi

  cbox::require_cmd git  || return 1
  cbox::require_cmd tmux || return 1
  cbox::require_cmd jq   || return 1
  cbox::engine_ready     || return 1

  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    cbox::log_err "not a git repository: $repo"
    return 1
  fi
  # Use the toplevel so worktree paths are stable regardless of where the
  # user invoked cbox from.
  repo=$(git -C "$repo" rev-parse --show-toplevel)

  local slug id branch worktree tmux_session
  slug=$(cbox::repo_slug "$repo")
  id=$(cbox::id)
  branch="cbox/${slug}-${id}"
  worktree="$(cbox::worktrees_dir)/${slug}-${id}"
  tmux_session="cbox-${slug}-${id}"

  mkdir -p "$(cbox::worktrees_dir)"
  if ! git -C "$repo" worktree add -b "$branch" "$worktree" HEAD; then
    cbox::log_err "git worktree add failed"
    return 1
  fi
  # Defuse the .git/hooks/ persistence path: an agent inside cbox could
  # write a pre-commit / post-checkout hook that the user later runs on
  # the host with full credentials. Pointing hooksPath at /dev/null means
  # git silently skips any executable in .git/hooks/ — both for this
  # worktree (when the user inspects with `git status` etc.) and from
  # inside the container (where it's harmless anyway). The user can still
  # opt back in by editing the worktree's local config.
  git -C "$worktree" config --local core.hooksPath /dev/null 2>/dev/null || true

  # Record state FIRST (under flock), then bring up proxy. If proxy_ensure
  # fails we roll back so we don't leave a phantom session that keeps the
  # refcount > 0 forever.
  if ! cbox::state_add "$id" "$repo" "$worktree" "$branch" "$tmux_session"; then
    cbox::log_err "failed to record session state"
    git -C "$repo" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
    git -C "$repo" branch -D "$branch" 2>/dev/null || true
    return 1
  fi

  if ! cbox::proxy_ensure; then
    cbox::log_err "proxy failed to start; rolling back session ${id}"
    cbox::state_remove "$id" || true
    git -C "$repo" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
    git -C "$repo" branch -D "$branch" 2>/dev/null || true
    return 1
  fi

  # Pick up any per-project allow-list edits that landed since last start.
  cbox::proxy_reload || cbox::log_warn "proxy reload failed; continuing with stale config"

  cbox::_session_build_engine_args "$worktree" "$id" "$tmux_session"

  if ! cbox::_session_spawn_tmux "$tmux_session" "$worktree" "${_CBOX_ENGINE_ARGS[@]}"; then
    cbox::log_err "failed to spawn session ${id}; rolling back"
    # Order matters: kill the engine first (it may have started detached
    # before tmux failed), then state, then worktree, then proxy.
    cbox::engine_stop "$tmux_session"
    cbox::engine_rm   "$tmux_session"
    cbox::state_remove "$id" || true
    git -C "$repo" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
    git -C "$repo" branch -D "$branch" 2>/dev/null || true
    cbox::proxy_stop_if_idle
    return 1
  fi

  cbox::log_ok "session ${id} (${slug}) on branch ${branch}"
  exec tmux attach -t "$tmux_session"
}

# cbox::session_attach [<id>]
#
# If the tmux session is alive: attach to it.
# If the tmux session is dead but the container is alive (the user exited
#   Claude with `/quit` or Ctrl-C; container kept running on `sleep infinity`):
#   transparently fall back to `cbox up <id>` so the user gets their session
#   back without thinking about the lifecycle distinction.
# If both are gone, the user wants `cbox` to start fresh — say so.
cbox::session_attach() {
  local id; id=$(cbox::_session_resolve_or_pick "${1:-}") || return 1
  local row tmux_session
  row=$(cbox::state_get "$id") || return 1
  tmux_session=$(printf '%s' "$row" | jq -r '.tmux')

  if cbox::_session_tmux_alive "$tmux_session"; then
    exec tmux attach -t "$tmux_session"
  fi

  # tmux is dead — check whether the container is still around. The container
  # name === tmux session name (set by runtime_args via --name). apple/container
  # `inspect` returns 0 even for unknown IDs, so use `list -a --quiet` for the
  # exists check.
  local cli; cli=$(cbox::engine_cli)
  if "$cli" list -a --quiet 2>/dev/null | grep -qx "$tmux_session"; then
    cbox::log "tmux session was closed but container ${tmux_session} is still alive; reattaching"
    cbox::session_up "$id"
    return $?
  fi

  cbox::log_err "session ${id} has no live tmux and no live container."
  cbox::log_err "  worktree is preserved at $(printf '%s' "$row" | jq -r '.worktree')"
  cbox::log_err "  run \`cbox rm ${id}\` to clean up, or \`cbox up ${id}\` to start a fresh container against the worktree"
  return 1
}

# cbox::session_stop [<id>]
#
# Force-removes the container + kills tmux. Worktree + state are PRESERVED
# so the user can `cbox up <id>` later. Does NOT call proxy_stop_if_idle —
# the session still counts toward the refcount.
cbox::session_stop() {
  local id; id=$(cbox::_session_resolve_or_pick "${1:-}") || return 1
  local row tmux_session container_name
  row=$(cbox::state_get "$id") || return 1
  tmux_session=$(printf '%s' "$row" | jq -r '.tmux')
  container_name="$tmux_session"

  # Graceful container stop (sends SIGTERM, then removes when stopped).
  cbox::engine_stop "$container_name"
  if cbox::_session_tmux_alive "$tmux_session"; then
    tmux kill-session -t "$tmux_session" 2>/dev/null || true
  fi
  cbox::log_ok "session ${id} stopped (worktree preserved)"
}

# cbox::session_up <id>
#
# Restart a previously-stopped session. id is REQUIRED — fzf would be
# misleading since most live sessions are already running.
cbox::session_up() {
  local query="${1:?cbox::session_up requires a session id}"
  local id; id=$(cbox::state_resolve_id "$query") || return 1
  local row repo worktree tmux_session
  row=$(cbox::state_get "$id") || return 1
  repo=$(printf '%s' "$row" | jq -r '.repo')
  worktree=$(printf '%s' "$row" | jq -r '.worktree')
  tmux_session=$(printf '%s' "$row" | jq -r '.tmux')

  if [[ ! -d "$worktree" ]]; then
    cbox::log_err "worktree no longer exists: $worktree"
    cbox::log_err "  run 'cbox rm --force $id' to clean up state"
    return 1
  fi

  if cbox::_session_tmux_alive "$tmux_session"; then
    cbox::log_err "session ${id} is already running. Use: cbox attach $id"
    return 1
  fi

  cbox::engine_ready || return 1
  cbox::proxy_ensure || return 1

  cbox::_session_build_engine_args "$worktree" "$id" "$tmux_session"
  if ! cbox::_session_spawn_tmux "$tmux_session" "$worktree" "${_CBOX_ENGINE_ARGS[@]}"; then
    cbox::log_err "failed to spawn tmux session ${tmux_session}"
    return 1
  fi
  cbox::log_ok "session ${id} restarted"
  _ignore_repo_unused() { :; }; _ignore_repo_unused "$repo"
  exec tmux attach -t "$tmux_session"
}

# cbox::session_rm [--force] [<id>]
cbox::session_rm() {
  local force=0
  if [[ "${1:-}" == "--force" ]]; then
    force=1; shift
  fi
  local id; id=$(cbox::_session_resolve_or_pick "${1:-}") || return 1
  local row repo worktree branch tmux_session container_name
  row=$(cbox::state_get "$id") || return 1
  repo=$(printf '%s' "$row" | jq -r '.repo')
  worktree=$(printf '%s' "$row" | jq -r '.worktree')
  branch=$(printf '%s' "$row" | jq -r '.branch')
  tmux_session=$(printf '%s' "$row" | jq -r '.tmux')
  container_name="$tmux_session"

  if (( force == 0 )); then
    if ! cbox::_session_branch_is_safe_to_remove "$repo" "$branch"; then
      cbox::log_err "branch ${branch} has unpushed commits."
      cbox::log_err "  push them, or re-run with --force to discard."
      return 1
    fi
  fi

  cbox::engine_stop "$container_name"
  cbox::engine_rm   "$container_name"   # belt-and-braces if stop+rm race
  if cbox::_session_tmux_alive "$tmux_session"; then
    tmux kill-session -t "$tmux_session" 2>/dev/null || true
  fi
  cbox::_session_remove_worktree "$repo" "$worktree"
  cbox::_session_maybe_delete_branch "$repo" "$branch"
  cbox::state_remove "$id"
  cbox::proxy_stop_if_idle
  cbox::log_ok "session ${id} removed"
}

# cbox::session_ls
#
# Pretty-prints the state list with a tmux-liveness column. Output is
# intentionally column-aligned but not machine-friendly — for scripting
# use `cbox::state_list` directly.
cbox::session_ls() {
  local rows
  rows=$(cbox::state_list)
  local count
  count=$(printf '%s' "$rows" | jq -r 'length')
  if [[ "$count" -eq 0 ]]; then
    printf 'no cbox sessions\n'
    return 0
  fi

  printf '%-7s %-20s %-30s %-9s %s\n' ID REPO BRANCH TMUX CREATED
  local id repo branch tmux_session created status repo_short branch_short
  while IFS=$'\t' read -r id repo branch tmux_session created; do
    if cbox::_session_tmux_alive "$tmux_session"; then
      status='alive'
    else
      status='dead'
    fi
    repo_short=$(basename "$repo")
    branch_short="${branch#cbox/}"
    printf '%-7s %-20s %-30s %-9s %s\n' \
      "$id" "${repo_short:0:20}" "${branch_short:0:30}" "$status" "$created"
  done < <(printf '%s' "$rows" | jq -r '.[] | [.id, .repo, .branch, .tmux, .created_at] | @tsv')
}

# cbox::session_pick [<query>]
#
# If a query is given, resolves it (prefix or exact). Otherwise launches
# fzf over the state list and prints the selected id.
cbox::session_pick() {
  local query="${1:-}"
  if [[ -n "$query" ]]; then
    cbox::state_resolve_id "$query"
    return $?
  fi

  cbox::require_cmd fzf || return 1
  local rows count
  rows=$(cbox::state_list)
  count=$(printf '%s' "$rows" | jq -r 'length')
  if [[ "$count" -eq 0 ]]; then
    cbox::log_err "no cbox sessions to pick from"
    return 1
  fi

  local picked
  picked=$(printf '%s' "$rows" \
    | jq -r '.[] | "\(.id)\t\(.repo)\t\(.branch)"' \
    | fzf --with-nth=1,2,3 --delimiter=$'\t' \
          --prompt='cbox session> ' \
          --header='ID  REPO  BRANCH') || return 1
  printf '%s\n' "$picked" | awk -F'\t' '{print $1}'
}

# cbox::session_prune [--apply]
#
# Finds sessions whose tmux is gone. Default is dry-run. With --apply,
# delegates to `cbox::session_rm --force <id>` for each.
cbox::session_prune() {
  local apply=0
  if [[ "${1:-}" == "--apply" ]]; then
    apply=1
  fi

  local rows
  rows=$(cbox::state_list)
  local total dead_ids
  total=$(printf '%s' "$rows" | jq -r 'length')
  if [[ "$total" -eq 0 ]]; then
    printf 'no cbox sessions\n'
    return 0
  fi

  dead_ids=()
  local id tmux_session
  while IFS=$'\t' read -r id tmux_session; do
    if ! cbox::_session_tmux_alive "$tmux_session"; then
      dead_ids+=("$id")
    fi
  done < <(printf '%s' "$rows" | jq -r '.[] | [.id, .tmux] | @tsv')

  if (( ${#dead_ids[@]} == 0 )); then
    printf 'no dead sessions\n'
    return 0
  fi

  if (( apply == 0 )); then
    printf 'would prune (dry run; pass --apply to execute):\n'
    local d
    for d in "${dead_ids[@]}"; do
      printf '  %s\n' "$d"
    done
    return 0
  fi

  local d
  for d in "${dead_ids[@]}"; do
    cbox::session_rm --force "$d" || cbox::log_warn "failed to prune $d"
  done
}
