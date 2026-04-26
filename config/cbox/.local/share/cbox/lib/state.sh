# cbox state — sessions.json read/write with atomic-rename concurrency.
# Schema:
#   { "version": "1",
#     "sessions": [
#       { "id": "k3p9xa", "repo": "...", "worktree": "...", "branch": "...",
#         "tmux": "...", "created_at": "2026-04-26T12:34:56Z" }, ... ] }
#
# Concurrency: every mutation acquires an exclusive lock on a sibling lock
# file/directory before reading-modifying-writing, then atomically renames a
# tmp file over sessions.json. Lock is released on subshell exit.
#
# Locking impl: prefer flock(1) when available; otherwise fall back to a
# mkdir-based mutex (mkdir is atomic on POSIX filesystems). macOS does not
# ship flock, so the fallback is the common path on dev workstations.

cbox::_state_file() { printf '%s\n' "$(cbox::state_dir)/sessions.json"; }

cbox::state_init() {
  local dir state
  dir=$(cbox::state_dir)
  state=$(cbox::_state_file)
  mkdir -p "$dir"
  if [[ ! -f "$state" ]]; then
    printf '{"version":"1","sessions":[]}\n' > "$state"
  fi
}

# Run a command (function name + args) under the state-file lock with an
# atomic rename. The callback receives two args: input file path (current
# sessions.json) and output file path (tmp it must write to). On success the
# helper renames tmp over sessions.json. On failure (non-zero exit, missing
# tmp) it leaves sessions.json untouched and returns the callback's status.
cbox::_state_with_lock() {
  local cb="${1:?_state_with_lock requires a callback}"; shift
  local state lock_dir tmp rc=0
  state=$(cbox::_state_file)
  lock_dir="${state}.lock.d"
  cbox::state_init
  if command -v flock >/dev/null 2>&1; then
    local lock_file="${state}.lock"
    (
      flock -x 9
      tmp=$(mktemp "${state}.XXXXXX")
      if "$cb" "$state" "$tmp" "$@"; then
        mv "$tmp" "$state"
      else
        rc=$?
        rm -f "$tmp"
        exit "$rc"
      fi
    ) 9>"$lock_file"
    rc=$?
  else
    # mkdir-based mutex with bounded spin.
    local waited=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
      sleep 0.05
      waited=$((waited + 1))
      if [[ "$waited" -gt 600 ]]; then  # 30s ceiling
        cbox::log_err "timed out waiting for state lock at ${lock_dir}"
        return 1
      fi
    done
    tmp=$(mktemp "${state}.XXXXXX")
    if "$cb" "$state" "$tmp" "$@"; then
      mv "$tmp" "$state"
      rc=0
    else
      rc=$?
      rm -f "$tmp"
    fi
    rmdir "$lock_dir" 2>/dev/null || true
  fi
  return "$rc"
}

# Internal callbacks used by _state_with_lock. They take ($in, $out, ...).
cbox::_state_cb_add() {
  local in="$1" out="$2"
  local id="$3" repo="$4" worktree="$5" branch="$6" tmux="$7" now="$8"
  jq --arg id "$id" \
     --arg repo "$repo" \
     --arg wt "$worktree" \
     --arg br "$branch" \
     --arg tx "$tmux" \
     --arg now "$now" \
     '.sessions += [{id:$id, repo:$repo, worktree:$wt, branch:$br, tmux:$tx, created_at:$now}]' \
     "$in" > "$out"
}

cbox::_state_cb_remove() {
  local in="$1" out="$2" id="$3"
  jq --arg id "$id" '.sessions |= map(select(.id != $id))' "$in" > "$out"
}

cbox::state_add() {
  local id="${1:?id}" repo="${2:?repo}" worktree="${3:?worktree}" \
        branch="${4:?branch}" tmux="${5:?tmux}"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cbox::_state_with_lock cbox::_state_cb_add \
    "$id" "$repo" "$worktree" "$branch" "$tmux" "$now"
}

cbox::state_remove() {
  local id="${1:?id}"
  cbox::_state_with_lock cbox::_state_cb_remove "$id"
}

cbox::state_list() {
  cbox::state_init
  jq -c '.sessions' "$(cbox::_state_file)"
}

cbox::state_get() {
  local id="${1:?id}"
  cbox::state_init
  jq -e -c --arg id "$id" '.sessions[] | select(.id == $id)' "$(cbox::_state_file)"
}

cbox::state_resolve_id() {
  local query="${1:?query}"
  cbox::state_init
  local matches count
  matches=$(jq -r --arg q "$query" '.sessions[].id | select(startswith($q))' "$(cbox::_state_file)")
  # `grep -c` exits non-zero when no lines match, which would trip errexit.
  count=$(printf '%s' "$matches" | grep -c '^.' || true)
  if [[ "$count" -eq 0 ]]; then
    cbox::log_err "no session matches '$query'"
    return 1
  elif [[ "$count" -eq 1 ]]; then
    printf '%s\n' "$matches"
  else
    # Exact match wins over an otherwise-ambiguous prefix.
    if printf '%s\n' "$matches" | grep -qx -- "$query"; then
      printf '%s\n' "$query"
    else
      cbox::log_err "ambiguous prefix '$query' matches: $(printf '%s' "$matches" | tr '\n' ' ')"
      return 1
    fi
  fi
}
