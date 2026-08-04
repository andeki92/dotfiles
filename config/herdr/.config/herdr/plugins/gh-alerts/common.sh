#!/usr/bin/env bash
# Shared by needs-me-launch.sh, opened-by-me-launch.sh, renovate-launch.sh.
# Each entrypoint sets AGENT, STATE, CONFIG_FILE, and a `count` function
# named by COUNT_FN, then sources this file.

set -euo pipefail
PANE_ID="${HERDR_PANE_ID:?not running as a herdr pane}"
: "${AGENT:?AGENT not set}"
: "${STATE:?STATE not set}"
: "${CONFIG_FILE:?CONFIG_FILE not set}"
: "${COUNT_FN:?COUNT_FN not set}"

poll() {
  while true; do
    count=$("$COUNT_FN")
    if [ "$count" -gt 0 ]; then
      herdr pane report-agent "$PANE_ID" --source custom:gh-alerts --agent "$AGENT" --state "$STATE"
    else
      herdr pane report-agent "$PANE_ID" --source custom:gh-alerts --agent "$AGENT" --state idle
    fi
    herdr pane report-metadata "$PANE_ID" --source custom:gh-alerts --agent "$AGENT" \
      --display-agent "$count open"
    sleep 60
  done
}

poll &
trap 'kill %1 2>/dev/null' EXIT

cd "$HOME"
exec gh dash --config "$HERDR_PLUGIN_ROOT/$CONFIG_FILE"
