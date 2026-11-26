#!/usr/bin/env bash
# Wire Atuin's local-only agent history hooks into supported coding agents
# (such as Pi) without enabling sync, background daemon, MCP, or Threads.
# Safe to re-run after Atuin or agent upgrades (mirrors scripts/herdr-setup.sh).

set -euo pipefail

if ! command -v atuin >/dev/null 2>&1; then
  printf '[atuin-setup] ERROR: atuin not found on PATH (install via: mise install atuin)\n' >&2
  exit 1
fi

ATUIN_CFG_DIR="${ATUIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/atuin}"
export ATUIN_CONFIG_DIR="$ATUIN_CFG_DIR"

# Install Pi agent-history hook if Pi is installed (either on PATH or ~/.pi/agent exists).
if command -v pi >/dev/null 2>&1 || [[ -d "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" ]]; then
  if atuin setup --help 2>&1 | grep -q -- '--agent-history'; then
    atuin setup --only --agent-history --agents pi --no-threads --no-daemon --no-mcp --sync off
  elif atuin hook --help 2>&1 | grep -q 'install'; then
    atuin hook install pi
  else
    printf '[atuin-setup] WARN: unrecognized atuin CLI; could not install Pi hook\n' >&2
    exit 1
  fi
else
  printf '[atuin-setup] Pi not installed; skipping Pi agent-history hook.\n'
fi
