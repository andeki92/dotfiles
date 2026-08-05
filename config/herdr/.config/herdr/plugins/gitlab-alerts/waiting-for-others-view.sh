#!/usr/bin/env bash
set -euo pipefail
glab api graphql -f query='query {
  currentUser {
    authoredMergeRequests(state: opened) {
      nodes { title webUrl project { fullPath } }
    }
  }
}' | jq -r '
  .data.currentUser.authoredMergeRequests.nodes[]
  | "\(.project.fullPath)  \(.title)\n  \(.webUrl)\n"
'
