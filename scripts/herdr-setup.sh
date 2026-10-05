#!/usr/bin/env bash
set -euo pipefail

# Claude Code session identity, so herdr resumes each session after a server
# restart. Rerun after a herdr upgrade: it rewrites the hook if it changed.
herdr integration install claude

herdr plugin link "$HOME/.config/herdr/plugins/gh-alerts"
herdr plugin link "$HOME/.config/herdr/plugins/pr-status"
herdr plugin link "$HOME/.config/herdr/plugins/worktree-setup"

gh auth status || gh auth login

if ! gh extension list | grep -q dlvhdr/gh-dash; then
  gh extension install dlvhdr/gh-dash
fi
