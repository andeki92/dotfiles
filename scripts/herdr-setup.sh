#!/usr/bin/env bash
set -euo pipefail

herdr plugin link "$HOME/.config/herdr/plugins/gh-alerts"

gh auth status || gh auth login

if ! gh extension list | grep -q dlvhdr/gh-dash; then
  gh extension install dlvhdr/gh-dash
fi
