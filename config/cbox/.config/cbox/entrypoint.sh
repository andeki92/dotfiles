#!/usr/bin/env bash
# cbox container entrypoint — runs as the agent user.
# Egress is enforced by the host-side Squid proxy (HTTPS_PROXY env var
# injected by the host wrapper). This script only runs mise install if a
# config exists in the workspace, then exec's the user-supplied command.

set -euo pipefail
IFS=$'\n\t'

log() { printf '[entry] %s\n' "$*" >&2; }

# Pre-seed Claude's onboarding + trust state. Without ~/.claude.json
# (note: dotfile in $HOME, NOT inside ~/.claude/) holding the relevant
# flags, the TUI shows the theme picker + login wizard + trust-folder
# prompt on every launch even when CLAUDE_CODE_OAUTH_TOKEN is set.
#
# Flags we set:
#   hasCompletedOnboarding=true   skip the theme picker + login wizard
#   projects./workspace.hasTrustDialogAccepted=true
#                                  skip the trust prompt for /workspace
#   bypassPermissionsModeAccepted=true
#                                  acknowledge --dangerously-skip-permissions
if [[ ! -f "$HOME/.claude.json" ]]; then
  cat > "$HOME/.claude.json" <<'JSON'
{
  "hasCompletedOnboarding": true,
  "installMethod": "global",
  "bypassPermissionsModeAccepted": true,
  "projects": {
    "/workspace": {
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true,
      "allowedTools": []
    }
  }
}
JSON
  log "seeded ${HOME}/.claude.json (skip wizard + trust /workspace)"
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
