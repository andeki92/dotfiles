#!/usr/bin/env bats
#
# Tests for ../block-bash-file-edits.sh — the PreToolUse guard that stops Claude
# editing files through the shell (sed -i, heredoc/redirect writes, etc.) while
# letting legitimate shell work through.
#
# Run:  bats config/claude/.claude/hooks/test
# Needs: bats (mise: aqua:bats-core/bats-core), jq.

bats_require_minimum_version 1.5.0

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../block-bash-file-edits.sh"
}

# Feed a command string to the guard as its PreToolUse JSON payload on stdin.
# bats `run` captures the exit status: 0 = allow, 2 = block.
run_hook() {
  local payload
  payload="$(jq -nc --arg c "$1" '{tool_input: {command: $c}}')"
  run bash "$HOOK" <<<"$payload"
}

# --- Allowed: data that merely looks like shell ----------------------------

@test "allows git commit heredoc with arrow + prose in the body" {
  run_hook "git commit -F - <<'EOF'
feat: theming

Latte <-> Macchiato switch.
Mentions sed -i and cat > foo.sh in prose.
EOF
echo done"
  [ "$status" -eq 0 ]
}

@test "allows gh pr create heredoc body containing arrows" {
  run_hook "gh pr create -F - <<EOF
body > with <-> arrows
EOF"
  [ "$status" -eq 0 ]
}

@test "allows an edit idiom mentioned only inside a heredoc body" {
  run_hook "git commit -F - <<EOF
fix: stop using sed -i in the build script
EOF"
  [ "$status" -eq 0 ]
}

@test "allows an arrow inside a quoted echo after the heredoc" {
  run_hook "git commit -F - <<EOF
msg
EOF
echo \"=== done -> next ===\""
  [ "$status" -eq 0 ]
}

@test "allows a quoted '>' in an echo alongside a heredoc" {
  run_hook "cat <<EOF
x
EOF
echo \"x > y improvement\""
  [ "$status" -eq 0 ]
}

@test "allows a plain echo with an arrow and no heredoc" {
  run_hook 'echo "Latte <-> Macchiato"'
  [ "$status" -eq 0 ]
}

@test "allows a normal git commit -m with '>' in the message" {
  run_hook 'git commit -m "feat: x > y improvement"'
  [ "$status" -eq 0 ]
}

@test "allows a here-string (<<<), which has no body" {
  run_hook 'grep foo <<< "world"'
  [ "$status" -eq 0 ]
}

@test "allows a heredoc redirected to a temp path" {
  run_hook "cat > /tmp/x.sh <<EOF
hi
EOF"
  [ "$status" -eq 0 ]
}

# --- Blocked: genuine shell file writes ------------------------------------

@test "blocks cat > file.sh <<EOF (source target)" {
  run_hook "cat > deploy.sh <<EOF
echo hi
EOF"
  [ "$status" -eq 2 ]
}

@test "blocks cat <<EOF > config.yaml (redirect after heredoc)" {
  run_hook "cat <<EOF > config.yaml
k: v
EOF"
  [ "$status" -eq 2 ]
}

@test "blocks cat > x.json <<EOF" {
  run_hook "cat > x.json <<EOF
{\"a\": 1}
EOF"
  [ "$status" -eq 2 ]
}

@test "blocks an in-place sed on a source file" {
  run_hook "sed -i 's/a/b/' main.py"
  [ "$status" -eq 2 ]
}
