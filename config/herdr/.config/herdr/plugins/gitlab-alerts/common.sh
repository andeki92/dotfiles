#!/usr/bin/env bash
# Shared by waiting-for-you-launch.sh and waiting-for-others-launch.sh.
# Each entrypoint sets AGENT, STATE, VIEW_CMD (path to an executable view
# script), and a `count` function named by COUNT_FN, then sources this file.

set -euo pipefail
PANE_ID="${HERDR_PANE_ID:?not running as a herdr pane}"
: "${AGENT:?AGENT not set}"
: "${STATE:?STATE not set}"
: "${VIEW_CMD:?VIEW_CMD not set}"
: "${COUNT_FN:?COUNT_FN not set}"

sanitize_count() {
  local raw="$1"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo 0
  fi
}

poll() {
  while true; do
    count=$(sanitize_count "$("$COUNT_FN" 2>/dev/null || echo 0)")
    if [ "$count" -gt 0 ]; then
      herdr pane report-agent "$PANE_ID" --source custom:gitlab-alerts --agent "$AGENT" --state "$STATE"
    else
      herdr pane report-agent "$PANE_ID" --source custom:gitlab-alerts --agent "$AGENT" --state idle
    fi
    herdr pane report-metadata "$PANE_ID" --source custom:gitlab-alerts --agent "$AGENT" \
      --display-agent "$count open"
    sleep 60
  done
}

poll &
trap 'kill %1 2>/dev/null' EXIT

cd "$HOME"
exec watch -n 30 -- "$VIEW_CMD"
