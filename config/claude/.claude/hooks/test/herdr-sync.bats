#!/usr/bin/env bats
#
# Tests for ../herdr-sync.sh — the one Claude Code hook that keeps herdr in
# step with a session: labels the tab once from the first prompt, and
# mirrors the session's move into (or out of) a linked git worktree onto
# herdr's topology — open the worktree as a child workspace and move the
# Claude pane into it, or move it back to the parent when the session leaves.
#
# Run:  bats config/claude/.claude/hooks/test
# Needs: bats (mise: aqua:bats-core/bats-core), jq.

bats_require_minimum_version 1.5.0

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../herdr-sync.sh"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/herdr-calls"
  QUERIES="${BATS_TEST_TMPDIR}/herdr-queries"
  mkdir -p "$FAKE_BIN"
  : >"$CALLS"
  : >"$QUERIES"
  export CALLS QUERIES

  # On-disk shape of a main checkout and a linked worktree: git marks a
  # linked worktree with a `.git` *file* (pointing back at the main repo)
  # where the main checkout has a `.git` directory.
  REPO="${BATS_TEST_TMPDIR}/repo"
  WT="$REPO/.claude/worktrees/feat"
  mkdir -p "$REPO/.git" "$WT"
  echo "gitdir: $REPO/.git/worktrees/feat" >"$WT/.git"
  export REPO WT

  # A fake `herdr` standing in for the real CLI. Read-only queries answer
  # from FAKE_* env vars and log their argv to $QUERIES; every mutating
  # call logs its argv to $CALLS so tests assert on exactly what the hook
  # asked herdr to do.
  #
  #   FAKE_LIVE_WS    workspace the pane currently sits in (pane get)
  #   FAKE_TAB_LABEL  label of the pane's live tab w1:t1 (tab get)
  #   FAKE_SOURCE_WS  parent repo workspace (worktree list .source)
  #   FAKE_WT_OPEN_WS open_workspace_id for the linked entry, or "null"
  #   FAKE_WT_LINKED  "true" to list $WT as a linked worktree, else omitted
  #   FAKE_OPENED_WS  workspace id `worktree open` reports
  #   FAKE_MOVE_EXIT  exit status for `pane move` (default 0)
  cat >"$FAKE_BIN/herdr" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pane get")
    echo "$*" >>"$QUERIES"
    jq -nc --arg ws "$FAKE_LIVE_WS" \
      '{result: {pane: {pane_id: "w1:p1", workspace_id: $ws, tab_id: "w1:t1"}}}'
    ;;
  "tab get")
    echo "$*" >>"$QUERIES"
    jq -nc --arg l "$FAKE_TAB_LABEL" \
      '{result: {tab: {tab_id: "w1:t1", label: $l}}}'
    ;;
  "tab rename")
    echo "$*" >>"$CALLS"
    ;;
  "worktree list")
    echo "$*" >>"$QUERIES"
    # Refuse a --cwd that does not exist on disk. The real CLI walks up to
    # the enclosing repo instead, but a worktree checked out outside the
    # repository has nothing to walk up to once removed — the hook must not
    # lean on that.
    shift 2
    while [ $# -gt 0 ]; do
      if [ "$1" = "--cwd" ]; then
        [ -d "$2" ] || { echo '{"error":{"code":"invalid_cwd"}}' >&2; exit 1; }
      fi
      shift
    done
    if [ "${FAKE_WT_LINKED:-}" = "true" ]; then
      jq -nc --arg src "$FAKE_SOURCE_WS" --arg wt "$FAKE_WT" \
        --argjson open "${FAKE_WT_OPEN_WS:-null}" \
        '{result: {source: {source_workspace_id: $src, source_checkout_path: "/repo", repo_name: "repo"},
                   worktrees: [
                     {path: "/repo", is_linked_worktree: false, open_workspace_id: $src},
                     {path: $wt, is_linked_worktree: true, open_workspace_id: $open}]}}'
    else
      jq -nc --arg src "$FAKE_SOURCE_WS" \
        '{result: {source: {source_workspace_id: $src, source_checkout_path: "/repo", repo_name: "repo"},
                   worktrees: [{path: "/repo", is_linked_worktree: false, open_workspace_id: $src}]}}'
    fi
    ;;
  "worktree open")
    echo "$*" >>"$CALLS"
    jq -nc --arg ws "$FAKE_OPENED_WS" \
      '{result: {workspace: {workspace_id: $ws}, already_open: false}}'
    ;;
  "pane move")
    echo "$*" >>"$CALLS"
    exit "${FAKE_MOVE_EXIT:-0}"
    ;;
  "workspace close")
    echo "$*" >>"$CALLS"
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/herdr"

  export HERDR_ENV=1
  export HERDR_PANE_ID=w1:p1
  export FAKE_WT="$WT"
  export FAKE_LIVE_WS=w1
  export FAKE_TAB_LABEL=claude
  export FAKE_SOURCE_WS=w1
  export FAKE_WT_LINKED=true
  export FAKE_WT_OPEN_WS=null
  export FAKE_OPENED_WS=w9
}

run_hook_with_payload() {
  run env PATH="$1" bash "$HOOK" <<<"$2"
}

run_hook() {
  run_hook_with_payload "$FAKE_BIN:$PATH" "$1"
}

enter_payload() {
  jq -nc --arg cwd "$WT" \
    '{hook_event_name: "PostToolUse", tool_name: "EnterWorktree", cwd: $cwd,
      tool_input: {name: "feat"},
      tool_response: {worktreePath: $cwd, worktreeBranch: "worktree-feat"}}'
}

prompt_payload() {
  jq -nc --arg p "$1" --arg cwd "$REPO" \
    '{hook_event_name: "UserPromptSubmit", cwd: $cwd, prompt: $p}'
}

@test "first prompt labels a placeholder tab from the prompt" {
  run_hook "$(prompt_payload 'ship #218')"
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-ship-218" "$CALLS"
}

@test "slug drops a slash-command prefix and keeps the argument" {
  run_hook "$(prompt_payload '/akle-skills:ship #218')"
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-ship-218" "$CALLS"
}

@test "slug stops at the first prose after the references" {
  run_hook "$(prompt_payload 'ship #123 and then let us discuss bla bla bla')"
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-ship-123" "$CALLS"
}

@test "slug keeps a whole run of references, connectors included" {
  run_hook "$(prompt_payload 'ship #123, #213, and #456')"
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-ship-123-213-and-456" "$CALLS"
}

@test "slug keeps the first four words of prose, capped at 24 chars" {
  run_hook "$(prompt_payload $'We have our claude custom command to work in herdr - I want you to research\nsecond line ignored')"
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-we-have-our-claude" "$CALLS"
}

@test "a tab that already has a real label is never renamed" {
  export FAKE_TAB_LABEL=claude-ship-218
  run_hook "$(prompt_payload 'now do something else')"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]

  export FAKE_TAB_LABEL=cli
  run_hook "$(prompt_payload 'ship #218')"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "a bare herdr default label counts as a placeholder" {
  export FAKE_TAB_LABEL=3
  run_hook "$(prompt_payload 'ship #218')"
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-ship-218" "$CALLS"
}

@test "stop and agent dispatch no longer rename anything" {
  run_hook '{"hook_event_name":"Stop","cwd":"/x"}'
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  run_hook '{"hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"Research something"}}'
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "bounds a wedged herdr instead of hanging" {
  # A fake herdr whose `pane get` sleeps far longer than the hook's 5s
  # bound. If run_bounded's `timeout 5` didn't fire, this would take 20s+.
  slow_bin="${BATS_TEST_TMPDIR}/slow-bin"
  mkdir -p "$slow_bin"
  cat >"$slow_bin/herdr" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pane get") sleep 20 ;;
  *) echo "$*" >>"$CALLS" ;;
esac
EOF
  chmod +x "$slow_bin/herdr"

  start=$(date +%s)
  run_hook_with_payload "$slow_bin:$PATH" "$(prompt_payload 'ship #218')"
  elapsed=$(( $(date +%s) - start ))

  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  [ "$elapsed" -lt 10 ]
}

@test "the move carries the tab label across" {
  export FAKE_TAB_LABEL=claude-ship-218
  run_hook "$(enter_payload)"
  [ "$status" -eq 0 ]
  grep -qx "pane move w1:p1 --new-tab --workspace w9 --label claude-ship-218 --no-focus" "$CALLS"
}

exit_payload() {
  jq -nc --arg repo "$REPO" --arg wt "$WT" --arg action "$1" \
    '{hook_event_name: "PostToolUse", tool_name: "ExitWorktree", cwd: $repo,
      tool_input: {action: $action},
      tool_response: {action: $action, originalCwd: $repo, worktreePath: $wt,
                      worktreeBranch: "worktree-feat"}}'
}

@test "exit keep moves the pane back and leaves the child workspace open" {
  export FAKE_LIVE_WS=w9 FAKE_WT_OPEN_WS='"w9"'
  run_hook "$(exit_payload keep)"
  [ "$status" -eq 0 ]
  grep -qx "pane move w1:p1 --new-tab --workspace w1 --label claude --no-focus" "$CALLS"
  ! grep -q "workspace close" "$CALLS"
  ! grep -q "worktree open" "$CALLS"
}

@test "exit remove moves the pane back and closes the child workspace" {
  export FAKE_LIVE_WS=w9 FAKE_WT_OPEN_WS='"w9"'
  # ExitWorktree with action remove has already deleted the checkout by the
  # time the hook runs.
  rm -rf "$WT"
  run_hook "$(exit_payload remove)"
  [ "$status" -eq 0 ]
  grep -qx "pane move w1:p1 --new-tab --workspace w1 --label claude --no-focus" "$CALLS"
  grep -qx "workspace close w9" "$CALLS"
  # The pane must be out before the workspace goes.
  [ "$(grep -n 'pane move' "$CALLS" | cut -d: -f1)" -lt \
    "$(grep -n 'workspace close' "$CALLS" | cut -d: -f1)" ]
}

@test "session start in a worktree adopts it" {
  # `claude -w feat` from the repo tab: the worktree workspace already exists
  # (w9) but the pane still sits in the parent (w1). Reuse, don't reopen.
  export FAKE_LIVE_WS=w1 FAKE_WT_OPEN_WS='"w9"'
  payload="$(jq -nc --arg cwd "$WT" '{hook_event_name: "SessionStart", source: "startup", cwd: $cwd}')"
  run_hook "$payload"
  [ "$status" -eq 0 ]
  ! grep -q "worktree open" "$CALLS"
  grep -qx "pane move w1:p1 --new-tab --workspace w9 --label claude --no-focus" "$CALLS"
}

@test "already in the target workspace is a no-op" {
  # SessionStart on /compact, /clear or resume once already adopted.
  export FAKE_LIVE_WS=w9 FAKE_WT_OPEN_WS='"w9"'
  payload="$(jq -nc --arg cwd "$WT" '{hook_event_name: "SessionStart", source: "compact", cwd: $cwd}')"
  run_hook "$payload"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "session start in the main checkout asks herdr nothing" {
  # The common case — every plain `claude` launch, every /compact — must
  # cost no socket round-trips: the on-disk `.git` shape already says this
  # is not a linked worktree.
  payload="$(jq -nc --arg cwd "$REPO" '{hook_event_name: "SessionStart", source: "startup", cwd: $cwd}')"
  run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$QUERIES" ]
  [ ! -s "$CALLS" ]
}

@test "non-worktree cwd and missing prerequisites are silent no-ops" {
  # cwd has a `.git` file but herdr does not list it as a linked worktree
  # (a submodule checkout, say): herdr stays the authority.
  export FAKE_WT_LINKED=false
  run_hook "$(enter_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALLS" ]

  # Outside herdr.
  HERDR_ENV= run_hook "$(enter_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALLS" ]

  # No pane id.
  HERDR_PANE_ID= run_hook "$(enter_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALLS" ]

  # No herdr / no jq on PATH.
  for missing in herdr jq; do
    bare="${BATS_TEST_TMPDIR}/no-${missing}-bin"
    mkdir -p "$bare"
    for tool in bash sed tr grep cat printf head jq herdr; do
      [ "$tool" = "$missing" ] && continue
      src="$(command -v "$tool")"
      [ "$tool" = herdr ] && src="$FAKE_BIN/herdr"
      [ -n "$src" ] && ln -sf "$src" "$bare/$tool"
    done
    run_hook_with_payload "$bare" "$(enter_payload)"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -s "$CALLS" ]
  done
}

@test "failed pane move leaves the opened workspace and exits 0" {
  export FAKE_MOVE_EXIT=1
  run_hook "$(enter_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qx "worktree open --workspace w1 --path $WT --label repo/feat --no-focus" "$CALLS"
  ! grep -q "workspace close" "$CALLS"
}

@test "enter opens the worktree workspace and moves the pane into it" {
  run_hook "$(enter_payload)"
  [ "$status" -eq 0 ]
  grep -qx "worktree open --workspace w1 --path $WT --label repo/feat --no-focus" "$CALLS"
  grep -qx "pane move w1:p1 --new-tab --workspace w9 --label claude --no-focus" "$CALLS"
}
