# claude() — inside herdr, launch a bare `claude` (no args) in a new,
# focused herdr tab instead of the pane it was typed in. Any flags or
# subcommands (`-p`, `--resume`, `mcp`, ...), and any shell outside herdr or
# without herdr/jq on PATH, pass straight through to the real binary.
claude() {
  if [[ "${HERDR_ENV:-}" != "1" ]] || [[ -z "${HERDR_WORKSPACE_ID:-}" ]] \
    || (( $# > 0 )) \
    || ! command -v herdr >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1; then
    command claude "$@"
    return
  fi

  local created pane_id
  # herdr answers on stdout and refuses on stderr, one JSON document either
  # way; keep both so a refusal can be quoted back.
  created="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label claude --focus 2>&1)"
  pane_id="$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null | head -n1)"

  if [[ -z "$pane_id" ]]; then
    _claude_herdr_refused "$created"
    command claude
    return
  fi

  herdr pane run "$pane_id" "command claude" >/dev/null 2>&1
}

# herdr would not open the tab: say why in herdr's own words and hold the
# message until a key is pressed. Claude's fullscreen TUI wipes the pane a
# moment after launch, which is how a one-line "tab create failed" went
# unread for a day while a stale server refused every call.
_claude_herdr_refused() {
  local why
  why="$(printf '%s' "$1" \
    | jq -r 'select(.error != null) | "\(.error.code): \(.error.message | split("\n")[0])"' 2>/dev/null \
    | head -n1)"
  [[ -n "$why" ]] || why="${1%%$'\n'*}"
  [[ -n "$why" ]] || why="no response"
  print -u2 -- "herdr tab create failed — ${why}"
  print -u2 -- "Running claude in this pane instead; worktree workspaces will not follow the session in herdr until it works again."
  if [[ -t 0 && -t 2 ]]; then
    print -u2 -n -- "Press any key to continue… "
    read -sk 1
    print -u2 ""
  fi
}
