#!/usr/bin/env bash
set -euo pipefail

count_opened_by_me() {
  gh api graphql -f query='{ search(type: ISSUE, query: "is:pr is:open archived:false author:@me", first: 1) { issueCount } }' \
    -q '.data.search.issueCount' 2>/dev/null || echo 0
}

AGENT="waiting-on-others"
STATE="blocked"
CONFIG_FILE="opened-by-me.yml"
COUNT_FN=count_opened_by_me

source "$HERDR_PLUGIN_ROOT/common.sh"
