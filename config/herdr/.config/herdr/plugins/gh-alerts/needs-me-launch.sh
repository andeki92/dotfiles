#!/usr/bin/env bash
set -euo pipefail

count_needs_me() {
  local reviewer_count assignee_count
  reviewer_count=$(gh api graphql -f query='{ search(type: ISSUE, query: "is:pr is:open archived:false review-requested:@me", first: 1) { issueCount } }' \
    -q '.data.search.issueCount' 2>/dev/null || echo 0)
  assignee_count=$(gh api graphql -f query='{ search(type: ISSUE, query: "is:pr is:open archived:false assignee:@me", first: 1) { issueCount } }' \
    -q '.data.search.issueCount' 2>/dev/null || echo 0)
  echo $((reviewer_count + assignee_count))
}

AGENT="needs-you"
STATE="blocked"
CONFIG_FILE="needs-me.yml"
COUNT_FN=count_needs_me

source "$HERDR_PLUGIN_ROOT/common.sh"
