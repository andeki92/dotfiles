#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/setup'
  _cbox_test_setup
  source "${CBOX_LIB}/common.sh"
}

@test "cbox::id generates 6 lowercase Crockford base32 chars" {
  local id
  id=$(cbox::id)
  [[ ${#id} -eq 6 ]]
  [[ "$id" =~ ^[a-z2-9]+$ ]]
  # No ambiguous chars
  [[ ! "$id" =~ [0olui] ]]
}

@test "cbox::id is unique across many invocations" {
  local -A seen
  for _ in $(seq 1 100); do
    local id
    id=$(cbox::id)
    [[ -z "${seen[$id]:-}" ]] || fail "duplicate id: $id"
    seen[$id]=1
  done
}

@test "cbox::repo_slug from a git directory returns the repo name" {
  # Use a parent tmp dir + a clean (already-slug-shaped) repo name so the
  # equality holds — `mktemp -d` on macOS produces names with `.` and
  # mixed case which are not valid slugs.
  local parent
  parent=$(mktemp -d)
  local repo="${parent}/cleanrepo"
  mkdir -p "$repo"
  cd "$repo"
  git init -q .
  local slug
  slug=$(cbox::repo_slug "$PWD")
  [[ "$slug" == "$(basename "$PWD")" ]]
}

@test "cbox::repo_slug normalises uppercase and underscores" {
  local slug
  slug=$(cbox::repo_slug "/some/path/My_Repo")
  [[ "$slug" == "my-repo" ]]
}

@test "cbox::log_err writes to stderr with prefix" {
  run -1 bash -c "source '${CBOX_LIB}/common.sh'; cbox::log_err 'boom'; exit 1"
  [[ "$output" == *"cbox: boom"* ]]
}

@test "cbox::require_cmd succeeds for an existing binary" {
  cbox::require_cmd ls
}

@test "cbox::require_cmd fails clearly for a missing binary" {
  run cbox::require_cmd no-such-binary-12345
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"required command not found: no-such-binary-12345"* ]]
}
