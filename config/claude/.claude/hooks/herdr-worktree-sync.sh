#!/usr/bin/env bash
#
# herdr-worktree-sync.sh — Claude Code hook that mirrors the session's move
# into (or out of) a linked git worktree onto herdr's own topology.
#
# Wired in ~/.claude/settings.json under PostToolUse (matcher
# EnterWorktree|ExitWorktree) and SessionStart. When the session's cwd is a
# linked worktree, herdr opens it as a child workspace grouped under the
# repository (or reuses the one already open) and this hook moves the pane
# running Claude into a fresh focused tab there — so agent status lands on
# the worktree's own sidebar row. When the session leaves the worktree, the
# pane goes back to the parent workspace; if the worktree was removed on the
# way out, the child workspace is closed too.
#
# The pane is located by HERDR_PANE_ID, which herdr keeps valid as an alias
# after a move. HERDR_TAB_ID and HERDR_WORKSPACE_ID are launch-time snapshots
# that go stale the moment the pane moves, so the live workspace is always
# read back from `herdr pane get`.
#
# No-ops silently (exit 0) outside herdr, when herdr/jq aren't installed, when
# the cwd isn't a linked worktree, or when herdr refuses a step — this hook
# must never block or warn.
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

# Workspace the pane is in right now, by the herdr server's account.
live_workspace() {
  live_ws="$(run_bounded herdr pane get "$HERDR_PANE_ID" 2>/dev/null \
    | jq -r '.result.pane.workspace_id // empty' 2>/dev/null)"
  [ -n "$live_ws" ] || exit 0
}

# Move the Claude pane into a new focused tab of $1.
move_pane_to() {
  run_bounded herdr pane move "$HERDR_PANE_ID" --new-tab --workspace "$1" \
    --label claude --focus >/dev/null 2>&1
}

# Adopt: make sure the linked worktree at $cwd has a herdr workspace and put
# the pane in it.
adopt() {
  [ -n "$cwd" ] || exit 0
  # Git marks a linked worktree with a `.git` *file* pointing back at the
  # main repository; a main checkout has a `.git` directory. This runs on
  # every session start — including each /compact and /clear — so the common
  # case of a plain checkout must cost no socket round-trips at all. herdr
  # stays the authority on what the `.git` file actually belongs to.
  [ -f "$cwd/.git" ] || exit 0

  live_workspace
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
    target="$(run_bounded herdr worktree open --workspace "$parent" --path "$cwd" --no-focus 2>/dev/null \
      | jq -r '.result.workspace.workspace_id // empty' 2>/dev/null)"
  fi
  [ -n "$target" ] || exit 0
  [ "$target" != "$live_ws" ] || exit 0

  move_pane_to "$target"
  exit 0
}

# Leave: put the pane back in the worktree's parent workspace. The parent is
# looked up from the directory the session came from, not the worktree: with
# `action: remove` the worktree is already gone by the time this runs.
leave() {
  origin="$(field '.tool_response.originalCwd')"
  [ -n "$origin" ] || origin="$cwd"
  [ -n "$origin" ] || exit 0
  live_workspace
  parent="$(run_bounded herdr worktree list --cwd "$origin" 2>/dev/null \
    | jq -r '.result.source.source_workspace_id // empty' 2>/dev/null)"
  [ -n "$parent" ] || exit 0
  [ "$parent" != "$live_ws" ] || exit 0

  move_pane_to "$parent" || exit 0

  # The worktree was deleted on the way out: its workspace now points at a
  # directory that no longer exists, so close it after the pane is safely out.
  if [ "$(field '.tool_response.action')" = "remove" ]; then
    run_bounded herdr workspace close "$live_ws" >/dev/null 2>&1
  fi
  exit 0
}

case "$event/$tool" in
  PostToolUse/EnterWorktree) adopt ;;
  PostToolUse/ExitWorktree) leave ;;
  SessionStart/*) adopt ;;
esac
exit 0
