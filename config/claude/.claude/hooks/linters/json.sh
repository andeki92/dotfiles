#!/usr/bin/env bash
#
# linters/json.sh — validate a JSON file for the lint-dispatch hook.
#
# Args: $1 = absolute path to a .json file (guaranteed to exist by caller).
# This is a validity check, not a style check: `jq empty` parses the whole
# document and fails on malformed JSON, reporting the offending line/column.
set -uo pipefail

file="$1"

command -v jq >/dev/null 2>&1 || exit 0

if output="$(jq empty "$file" 2>&1)"; then
  exit 0
fi

{
  echo "Invalid JSON in $file:"
  echo "$output"
} >&2
exit 2
