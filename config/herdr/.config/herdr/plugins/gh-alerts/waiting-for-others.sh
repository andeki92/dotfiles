#!/usr/bin/env bash
set -euo pipefail

count_waiting_for_others() {
  gh api graphql -f query='{ search(type: ISSUE, query: "is:pr is:open archived:false author:@me", first: 1) { issueCount } }' \
    -q '.data.search.issueCount' 2>/dev/null || echo 0
}

AGENT="waiting-for-others"
STATE="blocked"
CONFIG_FILE="waiting-for-others.yml"
COUNT_FN=count_waiting_for_others

source "$HERDR_PLUGIN_ROOT/common.sh"
