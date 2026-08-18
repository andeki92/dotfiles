#!/usr/bin/env bash
#
# herdr-tab-sync.sh — Claude Code Stop hook that keeps the herdr tab label in
# sync with Claude Code's own auto-generated terminal title.
#
# Wired in ~/.claude/settings.json as a Stop hook. Claude Code's terminal
# title (visible to herdr as pane.terminal_title_stripped) already tracks
# what the conversation is about; this just mirrors it into the herdr tab
# label, which is what the sidebar and prefix+1..9 switching actually show.
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
# Claude Code's Stop event on a missing optional tool.
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 5 "$@"
  else
    "$@"
  fi
}

title="$(run_bounded herdr pane get "$HERDR_PANE_ID" 2>/dev/null \
  | jq -r '.result.pane.terminal_title_stripped // empty' 2>/dev/null)"
[ -n "$title" ] || exit 0

slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
slug="${slug:0:24}"
slug="${slug%-}"
[ -n "$slug" ] || exit 0

run_bounded herdr tab rename "$HERDR_TAB_ID" "claude-$slug" >/dev/null 2>&1
exit 0
