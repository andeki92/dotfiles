#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/setup'
  _cbox_test_setup
  source "${CBOX_LIB}/common.sh"
  source "${CBOX_LIB}/state.sh"
}

@test "cbox::state_init creates an empty sessions.json with correct shape" {
  cbox::state_init
  [[ -f "$(cbox::state_dir)/sessions.json" ]]
  [[ "$(jq -r '.version' "$(cbox::state_dir)/sessions.json")" == "1" ]]
  [[ "$(jq -r '.sessions | length' "$(cbox::state_dir)/sessions.json")" == "0" ]]
}

@test "cbox::state_add appends a session record" {
  cbox::state_init
  cbox::state_add "k3p9xa" "myrepo" "/tmp/wt/myrepo-k3p9xa" "cbox/myrepo-k3p9xa" "cbox-myrepo-k3p9xa"
  [[ "$(jq -r '.sessions | length' "$(cbox::state_dir)/sessions.json")" == "1" ]]
  [[ "$(jq -r '.sessions[0].id' "$(cbox::state_dir)/sessions.json")" == "k3p9xa" ]]
  [[ "$(jq -r '.sessions[0].repo' "$(cbox::state_dir)/sessions.json")" == "myrepo" ]]
}

@test "cbox::state_remove deletes by id" {
  cbox::state_init
  cbox::state_add "aaa222" "r1" "/tmp/r1" "b1" "t1"
  cbox::state_add "bbb333" "r2" "/tmp/r2" "b2" "t2"
  cbox::state_remove "aaa222"
  [[ "$(jq -r '.sessions | length' "$(cbox::state_dir)/sessions.json")" == "1" ]]
  [[ "$(jq -r '.sessions[0].id' "$(cbox::state_dir)/sessions.json")" == "bbb333" ]]
}

@test "cbox::state_resolve_id returns exact match" {
  cbox::state_init
  cbox::state_add "k3p9xa" "r" "/tmp/x" "b" "t"
  result=$(cbox::state_resolve_id "k3p9xa")
  [[ "$result" == "k3p9xa" ]]
}

@test "cbox::state_resolve_id resolves an unambiguous prefix" {
  cbox::state_init
  cbox::state_add "k3p9xa" "r" "/tmp/x" "b" "t"
  cbox::state_add "qqq222" "r" "/tmp/y" "b" "t"
  result=$(cbox::state_resolve_id "k3")
  [[ "$result" == "k3p9xa" ]]
}

@test "cbox::state_resolve_id fails on ambiguous prefix" {
  cbox::state_init
  cbox::state_add "k3p9xa" "r" "/tmp/x" "b" "t"
  cbox::state_add "k3xxxx" "r" "/tmp/y" "b" "t"
  run cbox::state_resolve_id "k3"
  [[ "$status" -ne 0 ]]
  # Check stderr separately if your impl logs there; combined output is fine for the substring check.
  [[ "$output" == *"ambiguous"* ]]
}

@test "cbox::state_resolve_id fails on unknown id" {
  cbox::state_init
  run cbox::state_resolve_id "zzz999"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no session"* ]]
}

@test "cbox::state_list returns sessions as JSON array" {
  cbox::state_init
  cbox::state_add "aaa222" "r1" "/tmp/r1" "b1" "t1"
  cbox::state_add "bbb333" "r2" "/tmp/r2" "b2" "t2"
  result=$(cbox::state_list)
  count=$(printf '%s' "$result" | jq -r '. | length')
  [[ "$count" == "2" ]]
}

@test "cbox::state_add rejects duplicate id" {
  cbox::state_init
  cbox::state_add "k3p9xa" "r1" "/tmp/x" "b1" "t1"
  run cbox::state_add "k3p9xa" "r2" "/tmp/y" "b2" "t2"
  [[ "$status" -ne 0 ]]
  # Only the original record remains.
  [[ "$(jq -r '.sessions | length' "$(cbox::state_dir)/sessions.json")" == "1" ]]
  [[ "$(jq -r '.sessions[0].repo' "$(cbox::state_dir)/sessions.json")" == "r1" ]]
}

@test "cbox::state_remove of non-existent id is a no-op (idempotent)" {
  cbox::state_init
  cbox::state_add "aaa222" "r" "/tmp/x" "b" "t"
  cbox::state_remove "nonexistent"  # should succeed without error
  [[ "$(jq -r '.sessions | length' "$(cbox::state_dir)/sessions.json")" == "1" ]]
  [[ "$(jq -r '.sessions[0].id' "$(cbox::state_dir)/sessions.json")" == "aaa222" ]]
}

@test "concurrent cbox::state_add invocations do not lose records" {
  cbox::state_init
  for i in $(seq 1 10); do
    (cbox::state_add "id$i" "r" "/tmp/$i" "b$i" "t$i") &
  done
  wait
  count=$(jq -r '.sessions | length' "$(cbox::state_dir)/sessions.json")
  [[ "$count" == "10" ]] || fail "expected 10 records, got $count"
}
