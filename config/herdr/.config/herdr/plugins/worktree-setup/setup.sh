#!/usr/bin/env bash
#
# setup.sh — make a linked worktree that herdr opens ready to work in, by
# copying the gitignored files the main checkout lists in `.worktreeinclude`
# (.env files, local settings, ...). Claude Code reads the same file and
# applies the same rule — a file is copied only when `.worktreeinclude`
# matches it *and* Git ignores it — so a worktree gets the same files
# whichever tool made it.
#
# Never overwrites a file already in the worktree, so reopening a checkout,
# or one Claude Code already filled, changes nothing. mise needs no step
# here: it shares trust with the main checkout across worktrees.
#
# No-op for a main checkout, an already-open workspace, or a repo without a
# `.worktreeinclude`.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
event="${HERDR_PLUGIN_EVENT_JSON:-}"
[ -n "$event" ] || exit 0
field() { printf '%s' "$event" | jq -r "$1 // empty" 2>/dev/null; }

[ "$(field '.data.already_open')" = "true" ] && exit 0
[ "$(field '.data.worktree.is_linked_worktree')" = "true" ] || exit 0
worktree="$(field '.data.worktree.path')"
main="$(field '.data.workspace.worktree.repo_root')"
[ -d "$worktree" ] && [ -d "$main" ] || exit 0
[ -f "$main/.worktreeinclude" ] || exit 0

# Untracked files the include patterns match, then only those Git ignores.
git -C "$main" ls-files --others --ignored -z \
  --exclude-from="$main/.worktreeinclude" 2>/dev/null \
  | while IFS= read -r -d '' file; do
    git -C "$main" check-ignore -q -- "$file" || continue
    [ -e "$worktree/$file" ] && continue
    mkdir -p "$(dirname "$worktree/$file")" \
      && cp -p "$main/$file" "$worktree/$file"
  done
exit 0
