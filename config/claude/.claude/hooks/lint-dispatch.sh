#!/usr/bin/env bash
#
# lint-dispatch.sh — Claude Code PostToolUse entrypoint for edit-time linting.
#
# Wired in ~/.claude/settings.json as the single PostToolUse hook for
# Write|Edit|MultiEdit. Claude pipes the tool call as JSON on stdin; we pull the
# edited file's path, map its extension to a linter in ./linters/, and run it.
#
# Contract with each linter (linters/<name>.sh), invoked as `<name>.sh <file>`:
#   exit 0  -> clean, or linter's tool not installed (never block on a missing
#              tool — a machine without yamllint should still be editable)
#   exit 2  -> lint errors; the linter has printed them to stderr. Claude Code
#              feeds that stderr back to the model as actionable feedback.
#
# Adding a language later = drop one linters/<ext>.sh file and add a case below.
# No settings.json change, no edit to this dispatcher's core logic.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINTERS_DIR="$HOOK_DIR/linters"

# Need jq to read the hook payload. If it's missing, degrade to a no-op rather
# than blocking every edit on this machine.
command -v jq >/dev/null 2>&1 || exit 0

file_path="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$file_path" ] || exit 0   # tool had no file_path (not an edit) — nothing to do
[ -f "$file_path" ] || exit 0   # file gone (e.g. deleted) — nothing to lint

# Lower-cased extension.
filename="${file_path##*/}"
ext="${filename##*.}"
ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

# Map extension -> linter script. Several extensions can share one linter.
case "$ext" in
  yml|yaml)  linter="yaml.sh" ;;
  json)      linter="json.sh" ;;
  sh|bash)   linter="sh.sh"   ;;
  *)         exit 0 ;;   # unhandled type — silent no-op
esac

script="$LINTERS_DIR/$linter"
[ -x "$script" ] || exit 0   # linter not present/executable — don't block edits

exec "$script" "$file_path"
