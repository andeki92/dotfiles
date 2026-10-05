#!/usr/bin/env bash
#
# pr-status.sh — put the pull request of the branch an agent pane works on,
# with its CI rollup, on that agent's sidebar row as the `$pr` token:
#
#   #218 ✓   GitHub PR, checks passed       !42 ●   GitLab MR, pipeline running
#   #218 ✗   checks failed or cancelled     #218 ◆  merged     #218 ⊘  closed
#
# No PR, no repo, or no forge CLI clears the token. Only panes running an
# agent are looked at, so focusing a plain shell costs nothing.
#
# The branch is read from the pane's workspace checkout first: herdr-sync.sh
# moves a Claude pane into its worktree's workspace, while the pane's own
# cwd stays wherever the shell started. A workspace that is not a git
# checkout falls back to the pane's cwd.
#
# Focus events are throttled per pane; a finished turn and the refresh action
# always run. Silent on every failure — this fires on each focus change.
set -uo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
source_id="dotfiles:pr-status"
throttle_seconds=30

command -v jq >/dev/null 2>&1 || exit 0

event="${HERDR_PLUGIN_EVENT:-}"
event_json="${HERDR_PLUGIN_EVENT_JSON:-}"
data() { printf '%s' "$event_json" | jq -r "$1 // empty" 2>/dev/null; }

pane_id="$(data '.data.pane_id')"
[ -n "$pane_id" ] || pane_id="${HERDR_PANE_ID:-}"
[ -n "$pane_id" ] || exit 0

# A turn ending is the moment worth a lookup; going busy is not.
if [ "$event" = "pane.agent_status_changed" ]; then
  case "$(data '.data.agent_status')" in
    done | idle) ;;
    *) exit 0 ;;
  esac
fi

pane="$("$herdr" pane get "$pane_id" 2>/dev/null)" || exit 0
[ -n "$(printf '%s' "$pane" | jq -r '.result.pane.agent // empty')" ] || exit 0

if [ "$event" = "pane.focused" ] && [ -n "${HERDR_PLUGIN_STATE_DIR:-}" ]; then
  stamp="$HERDR_PLUGIN_STATE_DIR/last-check.$(printf '%s' "$pane_id" | tr -c 'A-Za-z0-9' '_')"
  now="$(date +%s)"
  last="$(cat "$stamp" 2>/dev/null || echo 0)"
  [ $((now - last)) -ge "$throttle_seconds" ] || exit 0
  printf '%s\n' "$now" >"$stamp" 2>/dev/null
fi

set_token() {
  "$herdr" pane report-metadata "$pane_id" --source "$source_id" --token "pr=$1" >/dev/null 2>&1
}
clear_token() {
  "$herdr" pane report-metadata "$pane_id" --source "$source_id" --clear-token pr >/dev/null 2>&1
  exit 0
}

workspace_id="$(printf '%s' "$pane" | jq -r '.result.pane.workspace_id // empty')"
dir="$("$herdr" workspace get "$workspace_id" 2>/dev/null \
  | jq -r '.result.workspace.worktree.checkout_path // empty' 2>/dev/null)"
[ -n "$dir" ] || dir="$(printf '%s' "$pane" | jq -r '.result.pane.cwd // empty')"
[ -d "$dir" ] || clear_token

branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)" || clear_token
remote="$(git -C "$dir" remote get-url origin 2>/dev/null)" || clear_token

case "$remote" in
  *github*)
    command -v gh >/dev/null 2>&1 || clear_token
    pr="$(cd "$dir" && gh pr view "$branch" --json number,state,statusCheckRollup 2>/dev/null)" \
      || clear_token
    # Check runs carry status + conclusion, commit statuses a single state;
    # worst wins: any failure, then anything unfinished, then pass.
    label="$(printf '%s' "$pr" | jq -r '
      def ci:
        [.statusCheckRollup[]?
          | (.conclusion // .state // "") as $c
          | if ($c | test("FAILURE|ERROR|CANCELLED|TIMED_OUT|ACTION_REQUIRED|STARTUP_FAILURE")) then "fail"
            elif (.status // "COMPLETED") != "COMPLETED" or ($c | test("PENDING|EXPECTED")) then "pending"
            else "pass" end]
        | if index("fail") then " ✗" elif index("pending") then " ●" elif length > 0 then " ✓" else "" end;
      "#\(.number)" + (if .state == "MERGED" then " ◆" elif .state == "CLOSED" then " ⊘" else ci end)')"
    ;;
  *gitlab*)
    command -v glab >/dev/null 2>&1 || clear_token
    # `glab mr view <branch>` refuses a branch that has had several MRs (a
    # reused renovate branch), and the list omits the pipeline: take the
    # newest MR's iid from the list, then view that one.
    iid="$(cd "$dir" && glab mr list --source-branch "$branch" --all \
      --order created_at --sort desc --per-page 1 --output json 2>/dev/null \
      | jq -r '.[0].iid // empty' 2>/dev/null)"
    [ -n "$iid" ] || clear_token
    mr="$(cd "$dir" && glab mr view "$iid" --output json 2>/dev/null)" || clear_token
    label="$(printf '%s' "$mr" | jq -r '
      ((.head_pipeline // .pipeline // {}).status // "") as $p
      | "!\(.iid)" + (
          if .state == "merged" then " ◆"
          elif .state == "closed" then " ⊘"
          elif $p == "success" then " ✓"
          elif $p == "failed" or $p == "canceled" then " ✗"
          elif $p == "" or $p == "skipped" or $p == "manual" then ""
          else " ●" end)')"
    ;;
  *) clear_token ;;
esac

[ -n "$label" ] && [ "$label" != "null" ] || clear_token
set_token "$label"
