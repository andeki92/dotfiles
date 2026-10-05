#!/usr/bin/env bash
set -euo pipefail

# Claude Code session identity, so herdr resumes each session after a server
# restart. Rerun after a herdr upgrade: it rewrites the hook if it changed.
herdr integration install claude

herdr plugin link "$HOME/.config/herdr/plugins/pr-status"
