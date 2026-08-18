#!/usr/bin/env bash
#
# herdr-tab-sync.sh — Claude Code hook that keeps the herdr tab label in sync
# with what the conversation is actually doing.
#
# Wired in ~/.claude/settings.json under both Stop and PostToolUse (matcher
# Agent|Task). On Stop, it mirrors Claude Code's own auto-generated terminal
# title (pane.terminal_title_stripped) into the herdr tab label. That title
# freezes for the whole duration of a backgrounded subagent dispatch, so on
# PostToolUse for Agent/Task it instead sources the label from the dispatch's
# own tool_input.description — the one signal that's fresh at the moment the
# dead zone begins. Either way the result is the label the sidebar and
# prefix+1..9 switching actually show.
#
# No-ops silently (exit 0) outside herdr, or when herdr/jq aren't installed —
# this hook must never block or warn on a machine/session that isn't herdr.
set -uo pipefail

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] && [ -n "${HERDR_TAB_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Bound worst-case hang if the herdr server is wedged (both calls are local
# socket round-trips and should return near-instantly). Degrade to running
# unbounded if `timeout`/`gtimeout` isn't installed rather than blocking
# Claude Code's hook on a missing optional tool.
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
event="$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)"

if [ "$event" = "PostToolUse" ]; then
  title="$(printf '%s' "$payload" | jq -r '.tool_input.description // empty' 2>/dev/null)"
else
  title="$(run_bounded herdr pane get "$HERDR_PANE_ID" 2>/dev/null \
    | jq -r '.result.pane.terminal_title_stripped // empty' 2>/dev/null)"
fi
[ -n "$title" ] || exit 0

slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
slug="${slug:0:24}"
slug="${slug%-}"
[ -n "$slug" ] || exit 0

run_bounded herdr tab rename "$HERDR_TAB_ID" "claude-$slug" >/dev/null 2>&1
exit 0
