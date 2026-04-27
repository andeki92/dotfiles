#!/usr/bin/env bash
# cbox container entrypoint — runs as the agent user.
# Egress is enforced by the host-side Squid proxy (HTTPS_PROXY env var
# injected by the host wrapper). This script only runs mise install if a
# config exists in the workspace, then exec's the user-supplied command.

set -euo pipefail
IFS=$'\n\t'

log() { printf '[entry] %s\n' "$*" >&2; }

# Pre-seed Claude's onboarding + trust state.
#
# ~/.claude.json (dotfile in $HOME, NOT inside ~/.claude/) holds the
# wizard + per-project trust state. Without it, the TUI shows the theme
# picker + login wizard + trust-folder prompt on every launch even when
# CLAUDE_CODE_OAUTH_TOKEN is set.
if [[ ! -f "$HOME/.claude.json" ]]; then
  cat > "$HOME/.claude.json" <<'JSON'
{
  "hasCompletedOnboarding": true,
  "installMethod": "global",
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

# Synthesize ~/.claude/settings.json by merging:
#   - the bypass-permissions skip flag (key per anthropics/claude-code#25503;
#     intentionally undocumented)
#   - host plugin keys forwarded via CBOX_HOST_CLAUDE_SETTINGS env (so plugins
#     enabled on the host — superpowers, rust-skills, etc. — work in here)
#
# We can't bind-mount the host's settings.json: apple/container 0.11 silently
# drops single-file mounts, and the host file leaks per-project Bash perms.
mkdir -p "$HOME/.claude"
if [[ ! -f "$HOME/.claude/settings.json" ]]; then
  if [[ -n "${CBOX_HOST_CLAUDE_SETTINGS:-}" ]] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$CBOX_HOST_CLAUDE_SETTINGS" \
      | jq '. + {"skipDangerousModePermissionPrompt": true}' \
      > "$HOME/.claude/settings.json"
    log "seeded ${HOME}/.claude/settings.json (host plugins + skip bypass warning)"
  else
    cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "skipDangerousModePermissionPrompt": true
}
JSON
    log "seeded ${HOME}/.claude/settings.json (skip bypass warning, no host plugins)"
  fi
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
