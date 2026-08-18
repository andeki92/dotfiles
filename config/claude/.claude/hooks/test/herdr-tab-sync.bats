#!/usr/bin/env bats
#
# Tests for ../herdr-tab-sync.sh — the Stop hook that mirrors Claude Code's
# auto-generated terminal title into the herdr tab label.
#
# Run:  bats config/claude/.claude/hooks/test
# Needs: bats (mise: aqua:bats-core/bats-core), jq.

bats_require_minimum_version 1.5.0

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../herdr-tab-sync.sh"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/herdr-calls"
  mkdir -p "$FAKE_BIN"
  : >"$CALLS"
  export CALLS

  # A fake `herdr` standing in for the real CLI. `pane get` answers with
  # $HERDR_FAKE_TITLE baked into terminal_title_stripped; `tab rename` just
  # logs its argv to $CALLS so tests can assert on the computed label.
  cat >"$FAKE_BIN/herdr" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pane get")
    jq -nc --arg t "$HERDR_FAKE_TITLE" \
      '{result: {pane: {terminal_title_stripped: $t}}}'
    ;;
  "tab rename")
    echo "$*" >>"$CALLS"
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/herdr"

  export HERDR_ENV=1
  export HERDR_PANE_ID=w1:p1
  export HERDR_TAB_ID=w1:t1
  export HERDR_FAKE_TITLE=""
}

# Runs the hook with an explicit PATH, scoped to this one invocation only —
# never mutates the test process's own PATH, which bats' own cleanup needs.
run_hook_with_path() {
  run env PATH="$1" bash "$HOOK"
}

run_hook() {
  run_hook_with_path "$FAKE_BIN:$PATH"
}

@test "renames the tab to a claude-prefixed slug of the terminal title" {
  export HERDR_FAKE_TITLE="Herdr Claude skill with tab automation"
  run_hook
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-herdr-claude-skill-with" "$CALLS"
}

@test "lowercases and collapses punctuation/whitespace runs into single hyphens" {
  export HERDR_FAKE_TITLE="Fix: Auth --- Middleware!!"
  run_hook
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-fix-auth-middleware" "$CALLS"
}

@test "skips the rename when the title is empty" {
  export HERDR_FAKE_TITLE=""
  run_hook
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "no-ops when HERDR_ENV is unset" {
  unset HERDR_ENV
  export HERDR_FAKE_TITLE="Some title"
  run_hook
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "no-ops when herdr is not on PATH" {
  export HERDR_FAKE_TITLE="Some title"
  no_herdr_bin="${BATS_TEST_TMPDIR}/no-herdr-bin"
  mkdir -p "$no_herdr_bin"
  for tool in bash sed tr grep cat printf jq; do
    src="$(command -v "$tool")"
    [ -n "$src" ] && ln -sf "$src" "$no_herdr_bin/$tool"
  done
  run_hook_with_path "$no_herdr_bin"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "bounds a wedged herdr instead of hanging" {
  # A fake herdr whose `pane get` sleeps far longer than the hook's 5s
  # bound. If run_bounded's `timeout 5` didn't fire, this test would take
  # 20s+ instead of ~5s.
  slow_bin="${BATS_TEST_TMPDIR}/slow-bin"
  mkdir -p "$slow_bin"
  cat >"$slow_bin/herdr" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pane get") sleep 20 ;;
  "tab rename") echo "$*" >>"$CALLS" ;;
esac
EOF
  chmod +x "$slow_bin/herdr"
  export HERDR_FAKE_TITLE="Some title"

  start=$(date +%s)
  run_hook_with_path "$slow_bin:$PATH"
  elapsed=$(( $(date +%s) - start ))

  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  [ "$elapsed" -lt 10 ]
}

@test "still renames when timeout/gtimeout are not on PATH (unbounded fallback)" {
  export HERDR_FAKE_TITLE="Some title"
  no_timeout_bin="${BATS_TEST_TMPDIR}/no-timeout-bin"
  mkdir -p "$no_timeout_bin"
  for tool in bash sed tr grep cat printf jq; do
    src="$(command -v "$tool")"
    [ -n "$src" ] && ln -sf "$src" "$no_timeout_bin/$tool"
  done
  ln -sf "$FAKE_BIN/herdr" "$no_timeout_bin/herdr"
  run_hook_with_path "$no_timeout_bin"
  [ "$status" -eq 0 ]
  grep -qx "tab rename w1:t1 claude-some-title" "$CALLS"
}

@test "no-ops when jq is not on PATH" {
  export HERDR_FAKE_TITLE="Some title"
  no_jq_bin="${BATS_TEST_TMPDIR}/no-jq-bin"
  mkdir -p "$no_jq_bin"
  for tool in bash sed tr grep cat printf; do
    src="$(command -v "$tool")"
    [ -n "$src" ] && ln -sf "$src" "$no_jq_bin/$tool"
  done
  ln -sf "$FAKE_BIN/herdr" "$no_jq_bin/herdr"
  run_hook_with_path "$no_jq_bin"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}
