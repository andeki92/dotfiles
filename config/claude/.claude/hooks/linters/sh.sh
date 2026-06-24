#!/usr/bin/env bash
#
# linters/sh.sh — lint a shell script for the lint-dispatch hook.
#
# Args: $1 = absolute path to a .sh/.bash file (guaranteed to exist by caller).
# shellcheck auto-detects the shell from the shebang; -x follows `source`d files.
set -uo pipefail

file="$1"

command -v shellcheck >/dev/null 2>&1 || exit 0

# -f gcc -> compact one-finding-per-line: file:line:col: level: message [SCxxxx]
if output="$(shellcheck -x -f gcc "$file" 2>&1)"; then
  exit 0
fi

{
  echo "shellcheck found problems in $file:"
  echo "$output"
} >&2
exit 2
