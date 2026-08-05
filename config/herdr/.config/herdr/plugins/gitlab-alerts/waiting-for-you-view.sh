#!/usr/bin/env bash
set -euo pipefail
glab api graphql -f query='query {
  currentUser {
    assignedMergeRequests(state: opened) {
      nodes { title webUrl project { fullPath } }
    }
    reviewRequestedMergeRequests(state: opened) {
      nodes { title webUrl project { fullPath } }
    }
  }
}' | jq -r '
  .data.currentUser
  | (.assignedMergeRequests.nodes + .reviewRequestedMergeRequests.nodes)
  | .[]
  | "\(.project.fullPath)  \(.title)\n  \(.webUrl)\n"
'
