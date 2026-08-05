#!/usr/bin/env bash
set -euo pipefail
ENTRYPOINT="$1"   # needs-me | opened-by-me

case "$ENTRYPOINT" in
  waiting-for-you)     TAB_LABEL="Waiting for you" ;;
  waiting-for-others)  TAB_LABEL="Waiting for others" ;;
  *)             TAB_LABEL="$ENTRYPOINT" ;;
esac

WS_ID=$(herdr workspace list | jq -r '.result.workspaces[]? | select(.label | ascii_downcase == "github") | .workspace_id' | head -n1)

if [ -z "${WS_ID:-}" ]; then
  WS_ID=$(herdr workspace create --label Github --no-focus | jq -r '.result.workspace.workspace_id')
fi

OPEN_RESULT=$(herdr plugin pane open --plugin dotfiles.gh-alerts --entrypoint "$ENTRYPOINT" \
  --placement tab --workspace "$WS_ID")

TAB_ID=$(echo "$OPEN_RESULT" | jq -r '.result.plugin_pane.pane.tab_id')

herdr tab rename "$TAB_ID" "$TAB_LABEL"
