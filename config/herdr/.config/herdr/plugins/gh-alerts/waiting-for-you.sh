#!/usr/bin/env bash
set -euo pipefail

count_waiting_for_you() {
  local reviewer_count assignee_count bot_count
  reviewer_count=$(gh api graphql -f query='{ search(type: ISSUE, query: "is:pr is:open archived:false review-requested:@me", first: 1) { issueCount } }' \
    -q '.data.search.issueCount' 2>/dev/null || echo 0)
  assignee_count=$(gh api graphql -f query='{ search(type: ISSUE, query: "is:pr is:open archived:false assignee:@me", first: 1) { issueCount } }' \
    -q '.data.search.issueCount' 2>/dev/null || echo 0)
  # author.type=="Bot" has no equivalent search qualifier, so this one still
  # has to fetch actual items rather than use issueCount.
  bot_count=$(gh search prs --owner=andeki92 --state=open --archived=false --limit=200 \
    --json number,author \
    -q '[.[] | select(.author.type=="Bot")] | length' 2>/dev/null || echo 0)
  echo $((reviewer_count + assignee_count + bot_count))
}

AGENT="waiting-for-you"
STATE="blocked"
CONFIG_FILE="waiting-for-you.yml"
COUNT_FN=count_waiting_for_you

source "$HERDR_PLUGIN_ROOT/common.sh"
