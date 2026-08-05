#!/usr/bin/env bash
set -euo pipefail

count_waiting_for_you() {
  glab api graphql -f query='query {
    currentUser {
      assignedMergeRequests(state: opened) { count }
      reviewRequestedMergeRequests(state: opened) { count }
    }
  }' 2>/dev/null | jq '.data.currentUser.assignedMergeRequests.count + .data.currentUser.reviewRequestedMergeRequests.count' 2>/dev/null || echo 0
}

AGENT="waiting-for-you"
STATE="blocked"
VIEW_CMD="$HERDR_PLUGIN_ROOT/waiting-for-you-view.sh"
COUNT_FN=count_waiting_for_you

source "$HERDR_PLUGIN_ROOT/common.sh"
