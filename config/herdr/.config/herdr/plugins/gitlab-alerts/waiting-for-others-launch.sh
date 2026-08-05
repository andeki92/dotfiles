#!/usr/bin/env bash
set -euo pipefail

count_waiting_for_others() {
  glab api graphql -f query='query {
    currentUser {
      authoredMergeRequests(state: opened) { count }
    }
  }' 2>/dev/null | jq '.data.currentUser.authoredMergeRequests.count' 2>/dev/null || echo 0
}

AGENT="waiting-for-others"
STATE="blocked"
VIEW_CMD="$HERDR_PLUGIN_ROOT/waiting-for-others-view.sh"
COUNT_FN=count_waiting_for_others

source "$HERDR_PLUGIN_ROOT/common.sh"
