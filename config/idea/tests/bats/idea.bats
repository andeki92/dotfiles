#!/usr/bin/env bats
#
# Fake `gh` and `glab` executables are placed first on PATH. Each one appends
# its own argv to a log and replays canned output, so these tests assert which
# provider calls `idea` makes and with which arguments — never that a real API
# agrees with them. `git` is deliberately not faked: every test runs inside a
# real temporary repository with a real `origin`, so remote-URL parsing is
# exercised against real `git` output.
#
# Log framing: one `=== <command>` line per invocation, then one tab-prefixed
# line per argument, with embedded newlines escaped to a literal `\n` so that a
# multi-line issue body cannot break the framing.

bats_require_minimum_version 1.5.0

setup() {
  IDEA_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  IDEA_BIN="${IDEA_ROOT}/.local/bin/idea"
  IDEA_TMP="$(mktemp -d -t idea-test.XXXXXX)"
  IDEA_STUB_BIN="${IDEA_TMP}/bin"
  export IDEA_STUB_DIR="${IDEA_TMP}/stubs"
  export IDEA_STUB_LOG="${IDEA_TMP}/calls.log"
  mkdir -p "$IDEA_STUB_BIN" "$IDEA_STUB_DIR"
  : > "$IDEA_STUB_LOG"

  make_stub gh
  make_stub glab
  export PATH="${IDEA_STUB_BIN}:${PATH}"

  IDEA_WORK="${IDEA_TMP}/repo"
  mkdir -p "$IDEA_WORK"
  git init -q "$IDEA_WORK"
  cd "$IDEA_WORK"
  set_origin "https://github.com/owner/repo.git"
}

teardown() {
  cd "$BATS_TEST_DIRNAME"
  [[ -n "${IDEA_TMP:-}" ]] && rm -rf "$IDEA_TMP"
}

# --- harness ---------------------------------------------------------------

# Write a fake provider CLI that records its argv and replays canned output.
# Canned files live in $IDEA_STUB_DIR keyed by command plus its first two
# arguments — `gh issue list` reads `gh-issue-list.out`. A `.exit` file sets
# the exit status, a `.err` file is written to stderr. Numbered variants
# (`<key>.1.out`, `<key>.2.out`) answer repeated calls to the same key in
# order, which is how the two reads behind `pick`'s detail view are told apart.
make_stub() {
  local name="$1"
  cat > "${IDEA_STUB_BIN}/${name}" <<'STUB'
#!/usr/bin/env bash
self="$(basename "$0")"
{
  printf '=== %s\n' "$self"
  for a in "$@"; do printf '\t%s\n' "${a//$'\n'/\\n}"; done
} >> "$IDEA_STUB_LOG"

key="$self"
[[ $# -ge 1 ]] && key="${key}-${1}"
[[ $# -ge 2 && "${2}" != -* ]] && key="${key}-${2}"

n=1
[[ -f "${IDEA_STUB_DIR}/${key}.n" ]] && n=$(cat "${IDEA_STUB_DIR}/${key}.n")
printf '%s' "$((n + 1))" > "${IDEA_STUB_DIR}/${key}.n"

# Only keys explicitly marked drain stdin: preflight runs before `idea new`
# reads its body, so a stub that always drained would eat the piped body.
[[ -f "${IDEA_STUB_DIR}/${key}.record-stdin" ]] && cat > "${IDEA_STUB_DIR}/${key}.stdin"

out="${IDEA_STUB_DIR}/${key}.${n}.out"
[[ -f "$out" ]] || out="${IDEA_STUB_DIR}/${key}.out"
[[ -f "$out" ]] && cat "$out"

err="${IDEA_STUB_DIR}/${key}.err"
[[ -f "$err" ]] && cat "$err" >&2

status="${IDEA_STUB_DIR}/${key}.exit"
[[ -f "$status" ]] && exit "$(cat "$status")"
exit 0
STUB
  chmod +x "${IDEA_STUB_BIN}/${name}"
}

set_origin() {
  git remote remove origin 2>/dev/null || true
  git remote add origin "$1"
}

# Canned stdout for a stub key, e.g. `stub_out gh-issue-list <<'EOF'`.
stub_out() { cat > "${IDEA_STUB_DIR}/${1}.out"; }
# Canned stdout for the <n>th call to a stub key.
stub_out_nth() { cat > "${IDEA_STUB_DIR}/${1}.${2}.out"; }
stub_exit() { printf '%s' "$2" > "${IDEA_STUB_DIR}/${1}.exit"; }
stub_err() { printf '%s\n' "$2" > "${IDEA_STUB_DIR}/${1}.err"; }

# Every recorded invocation of <command>, one space-joined line each.
calls() {
  awk -v want="$1" '
    /^=== / {
      if (matched) print line
      matched = (substr($0, 5) == want); line = ""; next
    }
    matched { a = substr($0, 2); line = (line == "" ? a : line " " a) }
    END { if (matched) print line }
  ' "$IDEA_STUB_LOG"
}

count_calls() { calls "$1" | grep -c . || true; }

# The argv of the <n>th (default 1st) invocation of <command>, one per line.
call_argv() {
  awk -v want="$1" -v want_n="${2:-1}" '
    /^=== / {
      if (substr($0, 5) == want) seen++
      matched = (substr($0, 5) == want && seen == want_n); next
    }
    matched { print substr($0, 2) }
  ' "$IDEA_STUB_LOG"
}

# True when the <n>th invocation of <command> passed <value> as a whole argument.
argv_has() {
  local value="$1" cmd="$2" n="${3:-1}"
  call_argv "$cmd" "$n" | grep -Fxq -- "$value"
}

no_provider_calls() { [[ ! -s "$IDEA_STUB_LOG" ]]; }

# --- provider detection and preflight --------------------------------------

@test "help prints usage and makes no provider call" {
  run "$IDEA_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"idea done"* ]]
  no_provider_calls
}

@test "an https github origin routes the preflight to gh" {
  run "$IDEA_BIN" done 7
  [ "$status" -eq 0 ]
  [[ "$(calls gh | head -1)" == "auth status" ]]
  [ "$(count_calls glab)" -eq 0 ]
}

@test "an scp-style github origin routes the preflight to gh" {
  set_origin "git@github.com:owner/repo.git"
  run "$IDEA_BIN" done 7
  [ "$status" -eq 0 ]
  [[ "$(calls gh | head -1)" == "auth status" ]]
  argv_has "owner/repo" gh 2
}

@test "a gitlab origin routes the preflight to glab and keeps subgroup paths" {
  set_origin "https://gitlab.com/group/sub/repo.git"
  run "$IDEA_BIN" done 7
  [ "$status" -eq 0 ]
  [[ "$(calls glab | head -1)" == "auth status" ]]
  [ "$(count_calls gh)" -eq 0 ]
  argv_has "group/sub/repo" glab 2
}

@test "an ssh url with an explicit port still yields owner/repo" {
  set_origin "ssh://git@github.com:22/owner/repo.git"
  run "$IDEA_BIN" done 7
  [ "$status" -eq 0 ]
  argv_has "owner/repo" gh 2
}

@test "an origin on an unsupported host errors without calling any provider" {
  set_origin "https://bitbucket.org/owner/repo.git"
  run "$IDEA_BIN" done 7
  [ "$status" -ne 0 ]
  [[ "$output" == *"bitbucket.org"* ]]
  [[ "$output" == *"github.com"* ]]
  [[ "$output" == *"gitlab.com"* ]]
  no_provider_calls
}

@test "a repository with no origin errors without calling any provider" {
  git remote remove origin
  run "$IDEA_BIN" done 7
  [ "$status" -ne 0 ]
  [[ "$output" == *"origin"* ]]
  no_provider_calls
}

@test "a missing provider CLI errors naming it" {
  run env PATH="/usr/bin:/bin" "$IDEA_BIN" done 7
  [ "$status" -ne 0 ]
  [[ "$output" == *"gh"* ]]
  [[ "$output" == *"not installed"* ]]
}

@test "an unauthenticated provider CLI errors naming it" {
  stub_exit gh-auth-status 1
  run "$IDEA_BIN" done 7
  [ "$status" -ne 0 ]
  [[ "$output" == *"gh"* ]]
  [[ "$output" == *"authenticated"* ]]
}

# --- idea new --------------------------------------------------------------

@test "new creates the issue on github with the given title" {
  run "$IDEA_BIN" new "speed up the dispatcher"
  [ "$status" -eq 0 ]
  argv_has "issue" gh 2
  argv_has "create" gh 2
  argv_has "--title" gh 2
  argv_has "speed up the dispatcher" gh 2
  argv_has "--repo" gh 2
  argv_has "owner/repo" gh 2
}

@test "new creates the issue on gitlab with the given title" {
  set_origin "https://gitlab.com/owner/repo.git"
  run "$IDEA_BIN" new "speed up the dispatcher"
  [ "$status" -eq 0 ]
  argv_has "create" glab 2
  argv_has "--title" glab 2
  argv_has "speed up the dispatcher" glab 2
  argv_has "owner/repo" glab 2
}

@test "size and tags become labels on the create call" {
  run "$IDEA_BIN" new "a title" --size M --tags "cli, perf"
  [ "$status" -eq 0 ]
  local create
  create="$(calls gh | tail -1)"
  [[ "$create" == *"--label size:M"* ]]
  [[ "$create" == *"--label cli"* ]]
  [[ "$create" == *"--label perf"* ]]
}

@test "size is rejected unless it is S, M or L" {
  run "$IDEA_BIN" new "a title" --size XL
  [ "$status" -ne 0 ]
  [[ "$output" == *"XL"* ]]
  [ "$(count_calls gh)" -le 1 ]
}

@test "every label is created before the issue that applies it" {
  run "$IDEA_BIN" new "a title" --size L --tags docs
  [ "$status" -eq 0 ]
  [[ "$(calls gh | sed -n 2p)" == "label create size:L --repo owner/repo" ]]
  [[ "$(calls gh | sed -n 3p)" == "label create docs --repo owner/repo" ]]
  [[ "$(calls gh | tail -1)" == "issue create"* ]]
}

@test "gitlab labels are created by name" {
  set_origin "https://gitlab.com/owner/repo.git"
  run "$IDEA_BIN" new "a title" --size S
  [ "$status" -eq 0 ]
  [[ "$(calls glab | sed -n 2p)" == "label create --name size:S --repo owner/repo" ]]
}

@test "a label that already exists is not a failure" {
  stub_exit gh-label-create 1
  stub_err gh-label-create "HTTP 422: Validation Failed. Name already_exists: must be unique"
  run "$IDEA_BIN" new "a title" --size M
  [ "$status" -eq 0 ]
  [[ "$(calls gh | tail -1)" == "issue create"* ]]
}

@test "a label that already exists is not a failure on gitlab either" {
  set_origin "https://gitlab.com/owner/repo.git"
  stub_exit glab-label-create 1
  stub_err glab-label-create "POST .../labels: 409 {message: Label already exists}"
  run "$IDEA_BIN" new "a title" --size M
  [ "$status" -eq 0 ]
  [[ "$(calls glab | tail -1)" == "issue create"* ]]
}

@test "a label failing for any other reason stops before creating the issue" {
  stub_exit gh-label-create 1
  stub_err gh-label-create "HTTP 403: Resource not accessible by personal access token"
  run "$IDEA_BIN" new "a title" --size M
  [ "$status" -ne 0 ]
  [[ "$output" == *"403"* ]]
  [[ "$(calls gh | tail -1)" != "issue create"* ]]
}

@test "a piped body reaches gh on stdin through the body-file flag" {
  : > "${IDEA_STUB_DIR}/gh-issue-create.record-stdin"
  run bash -c "printf 'first line\nsecond line' | '$IDEA_BIN' new 'a title'"
  [ "$status" -eq 0 ]
  argv_has "--body-file" gh 2
  argv_has "-" gh 2
  [[ "$(cat "${IDEA_STUB_DIR}/gh-issue-create.stdin")" == "first line
second line" ]]
}

@test "a piped body reaches glab as a literal description with yes" {
  set_origin "https://gitlab.com/owner/repo.git"
  run bash -c "printf 'first line\nsecond line' | '$IDEA_BIN' new 'a title'"
  [ "$status" -eq 0 ]
  argv_has "--description" glab 2
  argv_has 'first line\nsecond line' glab 2
  argv_has "--yes" glab 2
}

@test "a lone dash body gets a trailing space on gitlab" {
  set_origin "https://gitlab.com/owner/repo.git"
  run bash -c "printf '%s' - | '$IDEA_BIN' new 'a title'"
  [ "$status" -eq 0 ]
  argv_has "- " glab 2
  ! argv_has "-" glab 2
}

@test "a lone dash body is left alone on github" {
  : > "${IDEA_STUB_DIR}/gh-issue-create.record-stdin"
  run bash -c "printf '%s' - | '$IDEA_BIN' new 'a title'"
  [ "$status" -eq 0 ]
  [[ "$(cat "${IDEA_STUB_DIR}/gh-issue-create.stdin")" == "-" ]]
}

@test "the body flag supplies the body without reading stdin" {
  : > "${IDEA_STUB_DIR}/gh-issue-create.record-stdin"
  run bash -c "printf 'piped and ignored' | '$IDEA_BIN' new 'a title' --body 'from the flag'"
  [ "$status" -eq 0 ]
  [[ "$(cat "${IDEA_STUB_DIR}/gh-issue-create.stdin")" == "from the flag" ]]
}

@test "the body flag supplies the body on gitlab too" {
  set_origin "https://gitlab.com/owner/repo.git"
  run "$IDEA_BIN" new "a title" --body "from the flag"
  [ "$status" -eq 0 ]
  argv_has "--description" glab 2
  argv_has "from the flag" glab 2
  argv_has "--yes" glab 2
}

# --- idea done -------------------------------------------------------------

@test "done closes the issue on github with an explicit repo" {
  run "$IDEA_BIN" done 7
  [ "$status" -eq 0 ]
  [[ "$(calls gh | tail -1)" == "issue close 7 --repo owner/repo" ]]
}

@test "done closes the issue on gitlab with an explicit repo" {
  set_origin "https://gitlab.com/owner/repo.git"
  run "$IDEA_BIN" done 7
  [ "$status" -eq 0 ]
  [[ "$(calls glab | tail -1)" == "issue close 7 --repo owner/repo" ]]
}
