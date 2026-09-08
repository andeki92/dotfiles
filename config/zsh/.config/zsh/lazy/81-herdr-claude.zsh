# claude() — launch Claude Code through the headroom compression proxy when
# `headroom` is on PATH, and, inside herdr, put a bare `claude` (no args) in a
# new, focused herdr tab instead of the pane it was typed in.
#
# headroom: `headroom wrap claude` starts (or joins) one local proxy shared by
# every session on the machine, points this session's ANTHROPIC_BASE_URL at
# it, and records the tokens it saves (`headroom dashboard`, `headroom
# savings`). `--1m` keeps the [1m] context window Claude Code otherwise drops
# behind a custom base URL; `--code-memory none` skips the Serena MCP server.
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
    launch="headroom wrap claude --1m --code-memory none --"
  fi

  if [[ "${HERDR_ENV:-}" != "1" ]] || [[ -z "${HERDR_WORKSPACE_ID:-}" ]] \
    || (( $# > 0 )) \
    || ! command -v herdr >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1; then
    _claude_run ${=launch} "$@"
    return
  fi

  local created pane_id
  created="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label claude --focus 2>/dev/null)"
  pane_id="$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id // empty')"

  if [[ -z "$pane_id" ]]; then
    echo "herdr tab create failed; running claude here instead" >&2
    _claude_run ${=launch}
    return
  fi

  herdr pane run "$pane_id" "HERDR_AGENT=claude ${launch}" >/dev/null 2>&1
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
