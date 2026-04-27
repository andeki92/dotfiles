#!/usr/bin/env bash
# cbox container entrypoint — starts as root, drops to the agent user.
# Running as root lets us apply the firewall directly (no sudo needed, which
# means the container can keep --security-opt no-new-privileges enabled).
# Sequence: apply firewall (root) → drop to agent → mise install if a config
# exists → exec the user command (defaults to claude per CMD).
# All credential and config mounts are set up by the host wrapper before this
# script runs; here we only orchestrate startup.

set -euo pipefail
IFS=$'\n\t'

log() { printf '[entry] %s\n' "$*" >&2; }

# Phase 1 (root): firewall.
if [[ "$(id -u)" == "0" ]]; then
  log "applying firewall (as root)"
  /usr/local/bin/init-firewall.sh

  # Re-exec as the agent user with the same args. setpriv is in util-linux
  # (already in the base image) and is preferred over gosu (no extra package).
  AGENT_UID=$(id -u agent)
  AGENT_GID=$(id -g agent)
  log "dropping to agent (uid=$AGENT_UID gid=$AGENT_GID)"
  exec setpriv --reuid="$AGENT_UID" --regid="$AGENT_GID" --clear-groups \
       --reset-env -- env HOME=/home/agent PATH="$PATH" TERM="${TERM:-xterm}" \
       /usr/local/bin/entrypoint.sh "$@"
fi

# Phase 2 (agent): mise install + exec.
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
