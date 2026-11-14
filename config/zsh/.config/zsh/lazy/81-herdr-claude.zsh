# claude() — inside herdr, launch a bare `claude` (no args) in a new,
# focused herdr tab instead of the pane it was typed in. Any flags or
# subcommands (`-p`, `--resume`, `mcp`, ...), and any shell outside herdr or
# without herdr/jq on PATH, pass straight through to the real binary.
#
# Every session starts without your gitlab.com credential helper, the
# GIT_CONFIG_* trio eager/10-platform.zsh exports, so agents reach gitlab.com
# only through 0th's `1st`. `claude plugin ...` keeps it: adding and updating
# the private zeroth marketplace needs your glab login.
_claude_strip=(env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0)
claude() {
  [[ "${1:-}" == plugin ]] && { command claude "$@"; return; }
  (( $# == 0 )) && _claude_herdr_tab "${_claude_strip[*]} claude" && return
  "${_claude_strip[@]}" claude "$@"
}

# c — Claude Code with tracking on, so the flag-gated features DO_NOT_TRACK
# hides (/advisor among them) work, on the latest Opus at high effort with the
# latest Fable as advisor. Aliases, not version ids, so a new model needs no
# edit here. --effort is passed because Opus 5.5 and later ignore the
# top-level effortLevel setting and start at medium; the flag ranks below
# /effort, so a level picked mid-session still wins. A bare `c` opens its own
# herdr tab, as a bare `claude` does.
c() {
  local -a flags=(--model opus --effort high --advisor fable)
  (( $# == 0 )) && _claude_herdr_tab "${_claude_strip[*]} DO_NOT_TRACK=0 claude ${flags[*]}" && return
  "${_claude_strip[@]}" DO_NOT_TRACK=0 claude "${flags[@]}" "$@"
}

# _claude_herdr_tab <command line> — run the command line in a new, focused
# herdr tab. Returns 1 when it did not, outside herdr or when herdr refused,
# so the caller runs it in this pane instead.
_claude_herdr_tab() {
  if [[ "${HERDR_ENV:-}" != "1" ]] || [[ -z "${HERDR_WORKSPACE_ID:-}" ]] \
    || ! command -v herdr >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  local created pane_id
  # herdr answers on stdout and refuses on stderr, one JSON document either
  # way; keep both so a refusal can be quoted back.
  created="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label claude --focus 2>&1)"
  pane_id="$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null | head -n1)"

  if [[ -z "$pane_id" ]]; then
    _claude_herdr_refused "$created"
    return 1
  fi

  herdr pane run "$pane_id" "$1" >/dev/null 2>&1
  return 0
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
