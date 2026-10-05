#!/usr/bin/env bats
#
# Tests for ../setup.sh — the herdr worktree event hook that copies the
# gitignored files `.worktreeinclude` names into a new linked worktree.
#
# Run: bats config/herdr/.config/herdr/plugins/worktree-setup/test
# Needs: bats (mise: aqua:bats-core/bats-core), jq, git.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../setup.sh"
  MAIN="${BATS_TEST_TMPDIR}/repo"
  WT="${BATS_TEST_TMPDIR}/wt"

  # Keep the machine's git config and global excludes out of the repos.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/xdg"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  git init -q "$MAIN"
  printf '.env\nconfig/local.json\nnode_modules/\n' >"$MAIN/.gitignore"
  printf 'tracked\n' >"$MAIN/.env.example"
  git -C "$MAIN" add .gitignore .env.example
  git -C "$MAIN" commit -q -m init
  git -C "$MAIN" worktree add -q -b feat "$WT"

  printf 'SECRET=1\n' >"$MAIN/.env"
  mkdir -p "$MAIN/config" "$MAIN/node_modules/pkg"
  printf '{}\n' >"$MAIN/config/local.json"
  printf 'x\n' >"$MAIN/node_modules/pkg/index.js"
  printf 'scratch\n' >"$MAIN/untracked-not-ignored.env"
  # .env.example is tracked and *.env matches the untracked-but-not-ignored
  # file: neither may be copied. node_modules is ignored but not included.
  printf '.env\n.env.example\n*.env\nconfig/local.json\n' >"$MAIN/.worktreeinclude"
}

# run_event <event> <already_open> [is_linked_worktree]
run_event() {
  export HERDR_PLUGIN_EVENT="$1"
  HERDR_PLUGIN_EVENT_JSON="$(jq -nc --arg wt "$WT" --arg main "$MAIN" \
    --argjson open "$2" --argjson linked "${3:-true}" \
    '{data: {workspace: {worktree: {repo_root: $main, checkout_path: $wt}},
             worktree: {path: $wt, is_linked_worktree: $linked},
             already_open: $open}}')"
  export HERDR_PLUGIN_EVENT_JSON
  run bash "$SCRIPT"
}

@test "copies the ignored files .worktreeinclude names, and nothing else" {
  run_event worktree.opened false
  [ "$status" -eq 0 ]
  [ "$(cat "$WT/.env")" = "SECRET=1" ]
  [ -f "$WT/config/local.json" ]
  [ ! -e "$WT/node_modules" ]
  [ ! -e "$WT/untracked-not-ignored.env" ]
  [ "$(cat "$WT/.env.example")" = "tracked" ]
}

@test "worktree.created carries no already_open and still copies" {
  HERDR_PLUGIN_EVENT=worktree.created
  HERDR_PLUGIN_EVENT_JSON="$(jq -nc --arg wt "$WT" --arg main "$MAIN" \
    '{data: {workspace: {worktree: {repo_root: $main}},
             worktree: {path: $wt, is_linked_worktree: true}}}')"
  export HERDR_PLUGIN_EVENT HERDR_PLUGIN_EVENT_JSON
  run bash "$SCRIPT"
  [ -f "$WT/.env" ]
}

@test "never overwrites a file the worktree already has" {
  printf 'MINE=1\n' >"$WT/.env"
  run_event worktree.opened false
  [ "$(cat "$WT/.env")" = "MINE=1" ]
}

@test "an already-open workspace is left alone" {
  run_event worktree.opened true
  [ ! -e "$WT/.env" ]
}

@test "a main checkout is left alone" {
  run_event worktree.opened false false
  [ ! -e "$WT/.env" ]
}

@test "a repo without .worktreeinclude is left alone" {
  rm "$MAIN/.worktreeinclude"
  run_event worktree.opened false
  [ "$status" -eq 0 ]
  [ ! -e "$WT/.env" ]
}
