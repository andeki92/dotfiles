#!/usr/bin/env bash
# Install CLI tools if they're not already present.
# To add a tool, append a row: display name, check command, install command.
# Safe to re-run any number of times.

set -uo pipefail

TOOLS=(
  "Claude Code"      "claude" "curl -fsSL https://claude.ai/install.sh | bash"
  "Hugging Face CLI" "hf"     "curl -LsSf https://hf.co/cli/install.sh | bash"
)

if (( ${#TOOLS[@]} % 3 != 0 )); then
  echo "TOOLS array is malformed — each entry needs name, check command, install command" >&2
  exit 1
fi

install_if_missing() {
  local name="$1" check_cmd="$2" install_cmd="$3"

  if command -v "$check_cmd" &>/dev/null; then
    echo "✓ $name already installed ($(command -v "$check_cmd"))"
    return 0
  fi

  echo "Installing $name..."
  if bash -c "$install_cmd"; then
    echo "✓ $name installed successfully"
    return 0
  else
    echo "✗ $name installation failed" >&2
    return 1
  fi
}

failures=0
for ((i = 0; i < ${#TOOLS[@]}; i += 3)); do
  install_if_missing "${TOOLS[i]}" "${TOOLS[i + 1]}" "${TOOLS[i + 2]}" || failures=$((failures + 1))
done

echo
if [[ $failures -eq 0 ]]; then
  echo "All installers completed successfully."
else
  echo "$failures installer(s) failed — see output above." >&2
  exit 1
fi
