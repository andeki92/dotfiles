# claude() — inside herdr, launch a bare `claude` (no args) in a new,
# focused herdr tab instead of the pane it was typed in. Any flags or
# subcommands (`-p`, `--resume`, `mcp`, ...), and any shell outside herdr or
# without herdr/jq on PATH, pass straight through to the real binary.
claude() {
  if [[ "${HERDR_ENV:-}" != "1" ]] || (( $# > 0 )) \
    || ! command -v herdr >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1; then
    command claude "$@"
    return
  fi

  local created pane_id
  created="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label claude --focus 2>/dev/null)"
  pane_id="$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id // empty')"

  if [[ -z "$pane_id" ]]; then
    echo "herdr tab create failed; running claude here instead" >&2
    command claude
    return
  fi

  herdr pane run "$pane_id" "command claude" >/dev/null 2>&1
}
