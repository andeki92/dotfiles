#!/usr/bin/env bash
# cbox container entrypoint — runs as the agent user.
# Egress is enforced by the host-side Squid proxy (HTTPS_PROXY env var
# injected by the host wrapper). This script only runs mise install if a
# config exists in the workspace, then exec's the user-supplied command.

set -euo pipefail
IFS=$'\n\t'

log() { printf '[entry] %s\n' "$*" >&2; }

# Pre-seed Claude's onboarding state. Without ~/.claude.json (note: dotfile
# in $HOME, NOT inside ~/.claude/) holding hasCompletedOnboarding=true,
# the TUI shows the theme picker + login wizard on every launch — even
# when CLAUDE_CODE_OAUTH_TOKEN is set. The env-var token is only honoured
# in non-interactive (--print) mode unless this onboarding flag is also
# present.
if [[ ! -f "$HOME/.claude.json" ]]; then
  printf '{"hasCompletedOnboarding":true,"installMethod":"native"}\n' \
    > "$HOME/.claude.json"
  log "seeded ${HOME}/.claude.json (skip first-run wizard)"
fi

# mise: install toolchains if a config exists at /workspace.
if [[ -f /workspace/.mise.toml || -f /workspace/mise.toml || -f /workspace/.tool-versions ]]; then
  if [[ "${CBOX_MISE_INSTALL:-1}" == "1" ]]; then
    log "running mise install in /workspace"
    cd /workspace
    mise install || log "WARNING: mise install failed; continuing"
  else
    log "skipping mise install (CBOX_MISE_INSTALL=0)"
  fi
fi

cd /workspace
log "starting: $*"
exec "$@"
