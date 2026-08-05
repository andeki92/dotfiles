#!/usr/bin/env bash
set -euo pipefail

GITHUB_WS_ID=$(herdr workspace list | jq -r '.result.workspaces[]? | select(.label | ascii_downcase == "github") | .workspace_id' | head -n1)
GITLAB_WS_ID=$(herdr workspace list | jq -r '.result.workspaces[]? | select(.label | ascii_downcase == "gitlab") | .workspace_id' | head -n1)

if [ -n "${GITHUB_WS_ID:-}" ]; then
  herdr workspace close "$GITHUB_WS_ID"
fi

if [ -n "${GITLAB_WS_ID:-}" ]; then
  herdr workspace close "$GITLAB_WS_ID"
fi

# relink github-plugin
herdr plugin unlink dotfiles.gh-alerts
herdr plugin link "$HOME/.config/herdr/plugins/gh-alerts"

# relink gitlab-plugin
herdr plugin unlink dotfiles.gitlab-alerts
herdr plugin link "$HOME/.config/herdr/plugins/gitlab-alerts"

# open github panes
bash "$HOME/.config/herdr/plugins/gh-alerts/open-in-github-workspace.sh" waiting-for-you
bash "$HOME/.config/herdr/plugins/gh-alerts/open-in-github-workspace.sh" waiting-for-others

# open gitlab panes
bash "$HOME/.config/herdr/plugins/gitlab-alerts/open-in-gitlab-workspace.sh" waiting-for-you
bash "$HOME/.config/herdr/plugins/gitlab-alerts/open-in-gitlab-workspace.sh" waiting-for-others
