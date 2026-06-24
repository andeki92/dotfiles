#!/usr/bin/env bash
#
# linters/yaml.sh — lint a YAML file for the lint-dispatch hook.
#
# Args: $1 = absolute path to a .yml/.yaml file (guaranteed to exist by caller).
# yamllint reads its ruleset from ~/.config/yamllint/config (stowed) unless the
# project supplies its own .yamllint at the repo root.
set -uo pipefail

file="$1"

# Tool not installed on this machine -> no-op, never block editing.
command -v yamllint >/dev/null 2>&1 || exit 0

# -f parsable -> one finding per line: file:line:col: [level] message (rule)
if output="$(yamllint -f parsable "$file" 2>&1)"; then
  exit 0
fi

{
  echo "yamllint found problems in $file:"
  echo "$output"
} >&2
exit 2
