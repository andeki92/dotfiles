# Opt out of headroom's anonymous session-summary upload to Headroom Labs; it
# is on by default. Local savings tracking (`headroom savings`, the dashboard)
# is a separate switch and keeps working. Exported at file scope rather than
# inside claude() so every headroom invocation gets it, and read at process
# start, so the shared proxy only picks it up the next time it starts.
export HEADROOM_BEACON=off

# claude() — launch Claude Code through the headroom compression proxy when
# `headroom` is on PATH, and, inside herdr, put a bare `claude` (no args) in a
# new, focused herdr tab instead of the pane it was typed in.
#
# headroom: `headroom wrap claude` starts (or joins) one local proxy shared by
# every session on the machine, points this session's ANTHROPIC_BASE_URL at
# it, and records the tokens it saves (`headroom dashboard`, `headroom
# savings`). No `--1m` and no `--model`: both pin the model for every
# session (`--1m` via ANTHROPIC_MODEL, set to headroom's built-in Opus) and
# override the one `/model` saves to settings.json, which already keeps its
# 1M window behind the proxy. `--code-memory none` skips the Serena MCP server.
# Set CLAUDE_NO_HEADROOM=1 to launch the bare binary. Subcommands (`mcp`,
# `plugin`, ...) and `--version`/`--help` never go through the proxy.
#
# herdr: HERDR_AGENT=claude tells herdr which agent sits behind the wrapper
# process so pane status detection keeps working. Any flags (`-p`,
# `--resume`, ...), and any shell outside herdr or without herdr/jq on PATH,
# run in the current pane.
claude() {
  local launch="command claude"
  if [[ "${CLAUDE_NO_HEADROOM:-}" != "1" ]] \
    && command -v headroom >/dev/null 2>&1 \
    && _claude_is_session "$@"; then
    launch="headroom wrap claude --code-memory none --"
  fi

  if [[ "${HERDR_ENV:-}" != "1" ]] || [[ -z "${HERDR_WORKSPACE_ID:-}" ]] \
    || (( $# > 0 )) \
    || ! command -v herdr >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1; then
    _claude_run ${=launch} "$@"
    return
  fi

  local created pane_id
  # herdr answers on stdout and refuses on stderr, one JSON document either
  # way; keep both so a refusal can be quoted back.
  created="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label claude --focus 2>&1)"
  pane_id="$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null | head -n1)"

  if [[ -z "$pane_id" ]]; then
    _claude_herdr_refused "$created"
    _claude_run ${=launch}
    return
  fi

  herdr pane run "$pane_id" "HERDR_AGENT=claude ${launch}" >/dev/null 2>&1
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
  print -u2 -- "Running claude in this pane instead; tab labels and worktree workspaces will not sync to herdr until it works again."
  if [[ -t 0 && -t 2 ]]; then
    print -u2 -n -- "Press any key to continue… "
    read -sk 1
    print -u2 ""
  fi
}

# Run the launch command in this pane, tagged for herdr when inside it.
_claude_run() {
  if [[ "${HERDR_ENV:-}" == "1" ]]; then
    HERDR_AGENT=claude "$@"
  else
    "$@"
  fi
}

# True when the arguments start an interactive or print-mode session: no
# arguments, or a first argument that is a flag other than --version/--help.
_claude_is_session() {
  (( $# == 0 )) && return 0
  case "$1" in
    -v|--version|-h|--help) return 1 ;;
    -*) return 0 ;;
    *) return 1 ;;
  esac
}
