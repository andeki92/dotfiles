#!/usr/bin/env bash
set -euo pipefail

# author.type=="Bot" has no equivalent search qualifier, so this one still
# has to fetch actual items rather than use issueCount -- raise --limit well
# past the 30 default so large result sets aren't silently truncated.
count_renovate() {
  gh search prs --owner=andeki92 --state=open --archived=false --limit=200 \
    --json number,author \
    -q '[.[] | select(.author.type=="Bot")] | length' 2>/dev/null || echo 0
}

AGENT="renovate"
STATE="blocked"
CONFIG_FILE="renovate.yml"
COUNT_FN=count_renovate

source "$HERDR_PLUGIN_ROOT/common.sh"
