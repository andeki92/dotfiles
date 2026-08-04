#!/usr/bin/env bash
set -euo pipefail

WS_ID=$(herdr workspace list | jq -r '.result.workspaces[]? | select(.label | ascii_downcase == "github") | .workspace_id' | head -n1)

if [ -n "${WS_ID:-}" ]; then
  herdr workspace close "$WS_ID"
fi

herdr plugin unlink dotfiles.gh-alerts
herdr plugin link "$HOME/.config/herdr/plugins/gh-alerts"

bash "$HOME/.config/herdr/plugins/gh-alerts/open-in-github-workspace.sh" needs-me
bash "$HOME/.config/herdr/plugins/gh-alerts/open-in-github-workspace.sh" opened-by-me
bash "$HOME/.config/herdr/plugins/gh-alerts/open-in-github-workspace.sh" renovate
