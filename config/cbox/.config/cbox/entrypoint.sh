#!/usr/bin/env bash
# cbox container entrypoint — runs as the agent user.
# Sequence: apply firewall (sudo) → install mise toolchains if a config exists
# in the workspace → exec the user command (defaults to claude per CMD).
# All credential and config mounts are set up by the host wrapper before this
# script runs; here we only orchestrate startup.

set -euo pipefail
IFS=$'\n\t'

log() { printf '[entry] %s\n' "$*" >&2; }

log "applying firewall"
sudo /usr/local/bin/init-firewall.sh

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
