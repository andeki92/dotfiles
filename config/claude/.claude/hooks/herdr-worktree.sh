#!/usr/bin/env bash
#
# herdr-worktree.sh — when a Claude session moves into a git worktree, move
# its herdr pane into that worktree's workspace; when it leaves, move it back.
#
# herdr groups each worktree as a workspace under its repository, but it
# cannot see a worktree Claude Code creates on its own. This hook tells it:
#
#   EnterWorktree,       The session's cwd is a linked worktree: open it as a
#   SessionStart         workspace under the repo (or reuse the open one) and
#                        move the Claude pane into a new tab there.
#   ExitWorktree         Move the pane back to the repo's workspace, and close
#                        the worktree's workspace if the worktree was removed.
#
# Wired in ~/.claude/settings.json (PostToolUse EnterWorktree|ExitWorktree,
# SessionStart). Session state and resume are herdr's own integration hook,
# herdr-agent-state.sh beside this one; this hook never reports either.
#
# The pane is found by HERDR_PANE_ID, which herdr keeps valid after a move;
# HERDR_WORKSPACE_ID and HERDR_TAB_ID go stale, so where the pane is now is
# always read back from `herdr pane get`.
#
# Never blocks: exits 0 outside herdr, without herdr or jq, or when herdr
# refuses a step. The one thing it says out loud is a structured refusal of
# the pane lookup — `protocol_mismatch` after a Homebrew upgrade left the old
# server running — handed to Claude once per session as additionalContext.
set -uo pipefail

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Bound worst-case hang if the herdr server is wedged (all calls are local
# socket round-trips). Degrade to unbounded if timeout/gtimeout is missing.
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 5 "$@"
  else
    "$@"
  fi
}

payload="$(cat)"
field() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

event="$(field '.hook_event_name')"
tool="$(field '.tool_name')"
cwd="$(field '.cwd')"
# The id names a file below, so it is reduced to filename-safe characters.
session="$(field '.session_id' | tr -cd 'A-Za-z0-9._-')"

# Hand Claude one line of context, once per session, and stop.
notice() {
  marker="${TMPDIR:-/tmp}/herdr-worktree-notice.${session:-unknown}"
  if [ -n "$session" ]; then
    [ -e "$marker" ] && exit 0
    : >"$marker" 2>/dev/null
  fi
  jq -nc --arg ev "$event" --arg ctx "$1" \
    '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}'
  exit 0
}

# Where the pane is right now: sets live_ws and live_tab. herdr answers on
# stdout and refuses on stderr, one JSON document either way.
live_pane() {
  pane="$(run_bounded herdr pane get "$HERDR_PANE_ID" 2>&1)"
  live_ws="$(printf '%s' "$pane" | jq -r '.result.pane.workspace_id // empty' 2>/dev/null | head -n1)"
  live_tab="$(printf '%s' "$pane" | jq -r '.result.pane.tab_id // empty' 2>/dev/null | head -n1)"
  [ -n "$live_ws" ] && [ -n "$live_tab" ] && return

  code="$(printf '%s' "$pane" | jq -r '.error.code // empty' 2>/dev/null | head -n1)"
  [ -n "$code" ] || exit 0
  msg="$(printf '%s' "$pane" | jq -r '.error.message // empty' 2>/dev/null | head -n1)"
  notice "herdr-worktree hook: herdr refused this session's pane lookup ($code: $msg). Worktree workspaces are not being synced to herdr until that is fixed. Tell the user in one line. For protocol_mismatch the fix is restarting the herdr server at a good stopping point — stopping it exits every pane process, so it is the user's call, not yours."
}

# Move the Claude pane into a new tab of workspace $1, keeping the tab's
# label. Never focus: this runs mid-turn while the user may be typing
# elsewhere.
move_pane_to() {
  label="$(run_bounded herdr tab get "$live_tab" 2>/dev/null \
    | jq -r '.result.tab.label // empty' 2>/dev/null)"
  run_bounded herdr pane move "$HERDR_PANE_ID" --new-tab --workspace "$1" \
    --label "${label:-claude}" --no-focus >/dev/null 2>&1
}

enter() {
  [ -n "$cwd" ] || exit 0
  # A linked worktree has a `.git` *file*; a main checkout a directory. This
  # runs on every session start, /compact and /clear included, so a plain
  # checkout must cost no socket round-trips. herdr has the final say.
  [ -f "$cwd/.git" ] || exit 0

  live_pane
  listing="$(run_bounded herdr worktree list --cwd "$cwd" 2>/dev/null)"
  [ -n "$listing" ] || exit 0

  entry="$(printf '%s' "$listing" | jq -c --arg p "$cwd" \
    '.result.worktrees[]? | select(.path == $p and .is_linked_worktree == true)' \
    2>/dev/null | head -n1)"
  [ -n "$entry" ] || exit 0

  target="$(printf '%s' "$entry" | jq -r '.open_workspace_id // empty')"
  if [ -z "$target" ]; then
    parent="$(printf '%s' "$listing" | jq -r '.result.source.source_workspace_id // empty')"
    [ -n "$parent" ] || parent="$live_ws"
    # "<repo>/<worktree>": the agent panel lists worktree workspaces flat,
    # and an explicit label stops herdr's own drifting with the pane's cwd.
    repo="$(printf '%s' "$listing" | jq -r '.result.source.repo_name // empty')"
    wt_label="$(basename "$cwd")"
    [ -z "$repo" ] || wt_label="$repo/$wt_label"
    target="$(run_bounded herdr worktree open --workspace "$parent" --path "$cwd" \
      --label "$wt_label" --no-focus 2>/dev/null \
      | jq -r '.result.workspace.workspace_id // empty' 2>/dev/null)"
  fi
  [ -n "$target" ] || exit 0
  [ "$target" != "$live_ws" ] || exit 0

  move_pane_to "$target"
  exit 0
}

# The parent is looked up from the directory the session came from: with
# `action: remove` the worktree is already gone by the time this runs.
leave() {
  origin="$(field '.tool_response.originalCwd')"
  [ -n "$origin" ] || origin="$cwd"
  [ -n "$origin" ] || exit 0
  live_pane
  parent="$(run_bounded herdr worktree list --cwd "$origin" 2>/dev/null \
    | jq -r '.result.source.source_workspace_id // empty' 2>/dev/null)"
  [ -n "$parent" ] || exit 0
  [ "$parent" != "$live_ws" ] || exit 0

  move_pane_to "$parent" || exit 0

  # Close the removed worktree's workspace once the pane is safely out.
  if [ "$(field '.tool_response.action')" = "remove" ]; then
    run_bounded herdr workspace close "$live_ws" >/dev/null 2>&1
  fi
  exit 0
}

case "$event/$tool" in
  PostToolUse/EnterWorktree | SessionStart/*) enter ;;
  PostToolUse/ExitWorktree) leave ;;
esac
exit 0
