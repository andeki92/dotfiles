#!/usr/bin/env bats
#
# Tests for ../pr-status.sh — the herdr event hook that puts an agent pane's
# PR / MR and CI rollup on its sidebar row as the `$pr` token.
#
# Run: bats config/herdr/.config/herdr/plugins/pr-status/test
# Needs: bats (mise: aqua:bats-core/bats-core), jq, git.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../pr-status.sh"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  mkdir -p "$FAKE_BIN"
  : >"$CALLS"
  export CALLS

  # Keep the machine's git config out of the repos.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  # Two real checkouts on different branches: the pane's own cwd and the
  # workspace's worktree checkout, so the test can tell which one was read.
  CWD_REPO="${BATS_TEST_TMPDIR}/cwd-repo"
  WT_REPO="${BATS_TEST_TMPDIR}/wt-repo"
  for repo in "$CWD_REPO" "$WT_REPO"; do
    git init -q "$repo"
    git -C "$repo" commit -q --allow-empty -m init
    git -C "$repo" remote add origin git@github.com:me/repo.git
  done
  git -C "$CWD_REPO" checkout -q -b main-branch
  git -C "$WT_REPO" checkout -q -b feat-branch

  # herdr is reached through HERDR_BIN_PATH. Read-only answers come from:
  #   FAKE_AGENT       agent on the pane ("" for a plain shell)
  #   FAKE_CHECKOUT    workspace worktree checkout_path ("" for none)
  # report-metadata calls are recorded in $CALLS.
  cat >"$FAKE_BIN/herdr" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pane get")
    jq -nc --arg a "$FAKE_AGENT" --arg cwd "$FAKE_CWD" \
      '{result: {pane: {pane_id: "w1:p1", workspace_id: "w1",
                        agent: (if $a == "" then null else $a end), cwd: $cwd}}}'
    ;;
  "workspace get")
    jq -nc --arg p "$FAKE_CHECKOUT" \
      '{result: {workspace: ({workspace_id: "w1"}
        + (if $p == "" then {} else {worktree: {checkout_path: $p}} end))}}'
    ;;
  "pane report-metadata")
    echo "$*" >>"$CALLS"
    ;;
esac
EOF
  # gh prints $FAKE_FORGE_JSON, or fails when it is empty (no PR). glab
  # answers `mr list` with the iid of $FAKE_FORGE_JSON (an empty list when
  # there is none) and `mr view` with the MR itself. Each call records the
  # branch (or iid) it was asked about.
  cat >"$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $3" >>"$CALLS"
[ -n "$FAKE_FORGE_JSON" ] || exit 1
printf '%s\n' "$FAKE_FORGE_JSON"
EOF
  cat >"$FAKE_BIN/glab" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  list)
    echo "glab $4" >>"$CALLS"
    if [ -n "$FAKE_FORGE_JSON" ]; then
      printf '%s' "$FAKE_FORGE_JSON" | jq -c '[{iid}]'
    else
      echo '[]'
    fi
    ;;
  view)
    echo "glab view $3" >>"$CALLS"
    printf '%s\n' "$FAKE_FORGE_JSON"
    ;;
esac
EOF
  chmod +x "$FAKE_BIN"/*

  export PATH="$FAKE_BIN:$PATH"
  export HERDR_BIN_PATH="$FAKE_BIN/herdr"
  export HERDR_PLUGIN_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  export FAKE_AGENT=claude
  export FAKE_CWD="$CWD_REPO"
  export FAKE_CHECKOUT="$WT_REPO"
  export FAKE_FORGE_JSON=""
}

# run_event <event> [agent_status]
run_event() {
  export HERDR_PLUGIN_EVENT="$1"
  HERDR_PLUGIN_EVENT_JSON="$(jq -nc --arg s "${2:-}" \
    '{data: ({pane_id: "w1:p1"} + (if $s == "" then {} else {agent_status: $s} end))}')"
  export HERDR_PLUGIN_EVENT_JSON
  run bash "$SCRIPT"
}

github_pr() { # <state> <checks-json>
  jq -nc --arg s "$1" --argjson c "$2" '{number: 218, state: $s, statusCheckRollup: $c}'
}

token() { grep 'report-metadata' "$CALLS" | tail -n1; }

@test "open PR with passing checks shows a tick" {
  FAKE_FORGE_JSON="$(github_pr OPEN '[{"status":"COMPLETED","conclusion":"SUCCESS"},{"status":"COMPLETED","conclusion":"SKIPPED"}]')"
  export FAKE_FORGE_JSON
  run_event pane.focused
  [[ "$(token)" == *"--token pr=#218 ✓" ]]
}

@test "any failed check wins over pending ones" {
  FAKE_FORGE_JSON="$(github_pr OPEN '[{"status":"IN_PROGRESS","conclusion":""},{"status":"COMPLETED","conclusion":"FAILURE"}]')"
  export FAKE_FORGE_JSON
  run_event pane.focused
  [[ "$(token)" == *"--token pr=#218 ✗" ]]
}

@test "an unfinished check run or pending commit status shows pending" {
  FAKE_FORGE_JSON="$(github_pr OPEN '[{"status":"COMPLETED","conclusion":"SUCCESS"},{"state":"PENDING"}]')"
  export FAKE_FORGE_JSON
  run_event pane.focused
  [[ "$(token)" == *"--token pr=#218 ●" ]]
}

@test "open PR without checks shows just the number" {
  FAKE_FORGE_JSON="$(github_pr OPEN '[]')"
  export FAKE_FORGE_JSON
  run_event pane.focused
  [[ "$(token)" == *"--token pr=#218" ]]
}

@test "merged and closed PRs get their own marks, whatever the checks say" {
  FAKE_FORGE_JSON="$(github_pr MERGED '[{"status":"COMPLETED","conclusion":"FAILURE"}]')"
  export FAKE_FORGE_JSON
  run_event pane.focused
  [[ "$(token)" == *"--token pr=#218 ◆" ]]

  FAKE_FORGE_JSON="$(github_pr CLOSED '[]')"
  run_event pane.agent_status_changed done
  [[ "$(token)" == *"--token pr=#218 ⊘" ]]
}

@test "a branch without a PR clears the token" {
  run_event pane.focused
  [[ "$(token)" == *"--clear-token pr" ]]
}

@test "GitLab remotes ask glab and show the MR with its pipeline" {
  git -C "$WT_REPO" remote set-url origin git@gitlab.com:me/repo.git
  FAKE_FORGE_JSON='{"iid":42,"state":"opened","head_pipeline":{"status":"running"}}'
  export FAKE_FORGE_JSON
  run_event pane.focused
  grep -qx 'glab feat-branch' "$CALLS"
  grep -qx 'glab view 42' "$CALLS"
  [[ "$(token)" == *"--token pr=!42 ●" ]]

  FAKE_FORGE_JSON='{"iid":42,"state":"opened","head_pipeline":{"status":"success"}}'
  run_event pane.agent_status_changed idle
  [[ "$(token)" == *"--token pr=!42 ✓" ]]
}

@test "a GitLab branch without an MR clears the token without viewing one" {
  git -C "$WT_REPO" remote set-url origin git@gitlab.com:me/repo.git
  run_event pane.focused
  ! grep -q '^glab view' "$CALLS"
  [[ "$(token)" == *"--clear-token pr" ]]
}

@test "the workspace's worktree checkout decides the branch over the pane cwd" {
  run_event pane.focused
  grep -qx 'gh feat-branch' "$CALLS"
}

@test "a workspace that is no checkout falls back to the pane cwd" {
  FAKE_CHECKOUT=""
  run_event pane.focused
  grep -qx 'gh main-branch' "$CALLS"
}

@test "panes without an agent are left alone" {
  FAKE_AGENT=""
  run_event pane.focused
  [ ! -s "$CALLS" ]
}

@test "an agent going busy is not worth a lookup" {
  run_event pane.agent_status_changed working
  [ ! -s "$CALLS" ]
}

@test "repeated focus inside the throttle window looks up once" {
  run_event pane.focused
  run_event pane.focused
  [ "$(grep -c '^gh ' "$CALLS")" -eq 1 ]
}

@test "a finished turn looks up even right after a focus" {
  run_event pane.focused
  run_event pane.agent_status_changed done
  [ "$(grep -c '^gh ' "$CALLS")" -eq 2 ]
}
