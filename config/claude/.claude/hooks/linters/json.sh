#!/usr/bin/env bash
#
# linters/json.sh — validate a JSON / JSONC file for the lint-dispatch hook.
#
# Args: $1 = absolute path to a .json file (guaranteed to exist by caller).
# Strict JSON is checked fast with `jq empty`. Files that fail strict parsing
# but are valid JSONC — comments + trailing commas, e.g. Zed / VS Code settings,
# tsconfig.json — are accepted via a string-aware fallback (lib/jsonc-check.py),
# so editor config files aren't falsely flagged. Genuinely malformed files fail.
set -uo pipefail

file="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v jq >/dev/null 2>&1 || exit 0

# Fast path: strict JSON.
if jq empty "$file" >/dev/null 2>&1; then
  exit 0
fi

# Fallback: tolerate JSONC when python3 is available to strip comments safely.
if command -v python3 >/dev/null 2>&1; then
  if err="$(python3 "$here/lib/jsonc-check.py" "$file" 2>&1)"; then
    exit 0
  fi
else
  # No python3 to validate JSONC — surface the strict jq error instead.
  err="$(jq empty "$file" 2>&1)"
fi

{
  echo "Invalid JSON in $file:"
  echo "$err"
} >&2
exit 2
