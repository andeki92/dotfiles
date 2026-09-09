#!/usr/bin/env bash
#
# herdr-sync.sh — the one Claude Code hook that keeps herdr in step with a
# session. Wired in ~/.claude/settings.json under UserPromptSubmit,
# PostToolUse (matcher EnterWorktree|ExitWorktree) and SessionStart; the
# payload's hook_event_name / tool_name picks the branch:
#
#   UserPromptSubmit     Label the tab once, from the first prompt — a tab
#                        still carrying a placeholder label ("claude" from
#                        the zsh wrapper, or a bare herdr default like "1")
#                        becomes e.g. "claude-ship-218". A tab that already
#                        has a real label is never touched, so the label
#                        stays what the session was started for.
#   EnterWorktree /      When the session's cwd is a linked git worktree,
#   SessionStart         herdr opens it as a child workspace grouped under
#                        the repository (or reuses the one already open) and
#                        the pane running Claude moves into a fresh focused
#                        tab there, keeping its label — so agent status lands
#                        on the worktree's own sidebar row.
#   ExitWorktree         The pane goes back to the parent workspace; if the
#                        worktree was removed on the way out, the child
#                        workspace is closed too.
#
# The pane is located by HERDR_PANE_ID, which herdr keeps valid as an alias
# after a move. HERDR_TAB_ID and HERDR_WORKSPACE_ID are launch-time snapshots
# that go stale the moment the pane moves, so the live tab and workspace are
# always read back from `herdr pane get`.
#
# No-ops silently (exit 0) outside herdr, when herdr/jq aren't installed, when
# nothing applies, or when herdr refuses a step — this hook must never block.
#
# The one thing it does say: when herdr answers the session's own pane lookup
# with a structured error (`protocol_mismatch` after a Homebrew upgrade left
# the old server running is the case that cost a day), it hands Claude one
# line of additionalContext, once per session, so the user hears "herdr is
# refusing, restart it" on the first turn instead of discovering a silently
# unlabelled tab and an unadopted worktree hours later. A wedged server that
# just times out stays silent — there is no message worth relaying.
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
# The id names a file below, so it is reduced to filename-safe characters
# first rather than trusted as one.
session="$(field '.session_id' | tr -cd 'A-Za-z0-9._-')"

# Hand Claude one line of context and stop. The hookSpecificOutput shape is
# the one form every wired event (SessionStart, UserPromptSubmit, PostToolUse)
# feeds into the conversation; plain stdout only does so for some of them.
# Said once per session — the marker keeps a persistent refusal from being
# repeated on every prompt.
notice() {
  marker="${TMPDIR:-/tmp}/herdr-sync-notice.${session:-unknown}"
  if [ -n "$session" ]; then
    [ -e "$marker" ] && exit 0
    : >"$marker" 2>/dev/null
  fi
  jq -nc --arg ev "$event" --arg ctx "$1" \
    '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}'
  exit 0
}

# Where the pane is right now, by the herdr server's account. herdr writes
# its answer to stdout and a refusal to stderr, each as one JSON document, so
# both are read together and told apart by shape.
live_pane() {
  pane="$(run_bounded herdr pane get "$HERDR_PANE_ID" 2>&1)"
  live_ws="$(printf '%s' "$pane" | jq -r '.result.pane.workspace_id // empty' 2>/dev/null | head -n1)"
  live_tab="$(printf '%s' "$pane" | jq -r '.result.pane.tab_id // empty' 2>/dev/null | head -n1)"
  [ -n "$live_ws" ] && [ -n "$live_tab" ] && return

  code="$(printf '%s' "$pane" | jq -r '.error.code // empty' 2>/dev/null | head -n1)"
  [ -n "$code" ] || exit 0
  msg="$(printf '%s' "$pane" | jq -r '.error.message // empty' 2>/dev/null | head -n1)"
  notice "herdr-sync hook: herdr refused this session's pane lookup ($code: $msg). Tab labels and worktree workspaces are not being synced to herdr until that is fixed. Tell the user in one line. For protocol_mismatch the fix is restarting the herdr server at a good stopping point — stopping it exits every pane process, so it is the user's call, not yours."
}

# The live tab's current label, or empty.
tab_label() {
  run_bounded herdr tab get "$live_tab" 2>/dev/null \
    | jq -r '.result.tab.label // empty' 2>/dev/null
}

# Move the Claude pane into a new tab of $1, keeping its label — the move
# usually comes after the first prompt has already named the tab. Never
# focus: the move happens mid-turn while the user may be typing in another
# pane, and the session is found again under its workspace when wanted.
move_pane_to() {
  label="$(tab_label)"
  [ -n "$label" ] || label=claude
  run_bounded herdr pane move "$HERDR_PANE_ID" --new-tab --workspace "$1" \
    --label "$label" --no-focus >/dev/null 2>&1
}

# Label: first prompt → "claude-<slug>", only while the tab still carries a
# placeholder. The slug comes from the prompt's first line with any
# slash-command prefix dropped ("/akle-skills:ship #218" → "ship #218"):
#
#   - a command followed by references keeps the command and the whole run
#     of references, connectors included, and drops everything after it:
#     "ship #123 and then let us discuss…" → "ship-123",
#     "ship #123, #213, and #456"          → "ship-123-213-and-456";
#   - anything else keeps its first four words.
#
# Lowercased, non-alphanumeric runs collapsed to "-", capped at 24 characters
# — short enough for the sidebar, long enough to keep the skill and what it
# was pointed at.
label() {
  live_pane
  case "$(tab_label)" in
    claude|'') ;;
    *[!0-9]*) exit 0 ;;
  esac

  prompt="$(field '.prompt' | head -n1)"
  prompt="${prompt#/}"
  prompt="$(printf '%s' "$prompt" | sed -E 's/^[A-Za-z0-9_-]+://')"
  # shellcheck disable=SC2206 # word-splitting on whitespace is the point
  words=($prompt)
  [ "${#words[@]}" -gt 0 ] || exit 0

  # A reference is "#" plus digits, with a trailing comma tolerated.
  is_ref() { [[ "${1%,}" =~ ^#[0-9]+$ ]]; }

  keep=("${words[0]}")
  i=1
  while [ "$i" -lt "${#words[@]}" ]; do
    w="${words[$i]}"
    if is_ref "$w"; then
      keep+=("${w%,}")
    elif [[ "${w%,}" =~ ^(and|&|\+)$ ]] && [ $((i + 1)) -lt "${#words[@]}" ] \
        && is_ref "${words[$((i + 1))]}"; then
      keep+=("and")
    else
      break
    fi
    i=$((i + 1))
  done
  if [ "${#keep[@]}" -eq 1 ]; then
    keep=("${words[@]:0:4}")
  fi

  slug="$(printf '%s ' "${keep[@]}" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  slug="${slug:0:24}"
  slug="${slug%-}"
  [ -n "$slug" ] || exit 0

  run_bounded herdr tab rename "$live_tab" "claude-$slug" >/dev/null 2>&1
  exit 0
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
    # Label as "<repo>/<worktree>": the agent panel lists worktree workspaces
    # flat, so a bare worktree name doesn't say which repository it came
    # from. An explicit label also stops herdr's automatic one drifting with
    # the pane's cwd.
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

# Leave: put the pane back in the worktree's parent workspace. The parent is
# looked up from the directory the session came from, not the worktree: with
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

  # The worktree was deleted on the way out: its workspace now points at a
  # directory that no longer exists, so close it after the pane is safely out.
  if [ "$(field '.tool_response.action')" = "remove" ]; then
    run_bounded herdr workspace close "$live_ws" >/dev/null 2>&1
  fi
  exit 0
}

case "$event/$tool" in
  UserPromptSubmit/*) label ;;
  PostToolUse/EnterWorktree) adopt ;;
  PostToolUse/ExitWorktree) leave ;;
  SessionStart/*) adopt ;;
esac
exit 0
