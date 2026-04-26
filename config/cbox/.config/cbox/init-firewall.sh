#!/usr/bin/env bash
# cbox firewall — applied at container start by entrypoint.sh.
# Drops all egress except an explicit allow-list. Package registries are NOT
# allowed by default; per-project work mounts /cbox/allowlist (one host per
# line) to extend the set.
#
# Runs as root inside the container (via the sudoers entry in the Containerfile).
# Modifies container-private iptables only — not host iptables (we use rootless
# Podman with a private network namespace).

set -euo pipefail
IFS=$'\n\t'

log()  { printf '[firewall] %s\n' "$*" >&2; }
fail() { printf '[firewall] FATAL: %s\n' "$*" >&2; exit 1; }

# Sanity.
[[ "$(id -u)" == "0" ]] || fail "must be run as root (use sudo)"
command -v iptables >/dev/null || fail "iptables not installed in image"
command -v ipset >/dev/null    || fail "ipset not installed in image"

# Reset.
log "flushing existing rules"
iptables -F
iptables -X
iptables -P INPUT   ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT  ACCEPT

# Allow loopback + established.
iptables -A OUTPUT  -o lo -j ACCEPT
iptables -A INPUT   -i lo -j ACCEPT
iptables -A INPUT   -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS — UDP/TCP 53 to public resolvers.
for dns in 1.1.1.1 8.8.8.8; do
  iptables -A OUTPUT -p udp --dport 53 -d "$dns" -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 53 -d "$dns" -j ACCEPT
done

# ipset for allowed hosts.
ipset destroy cbox-allow 2>/dev/null || true
ipset create  cbox-allow hash:net family inet hashsize 1024 maxelem 65536

# Track what we allowed for the ground-truth file.
DEFAULT_HOSTS=()
PROJECT_HOSTS=()

resolve_to_set() {
  local host="$1"
  local ip
  while read -r ip; do
    [[ -n "$ip" ]] || continue
    log "  $host -> $ip"
    ipset add cbox-allow "$ip" 2>/dev/null || true
  done < <(getent ahostsv4 "$host" | awk '/STREAM/ {print $1}' | sort -u)
}

allow_default() {
  log "allowing $1 (default)"
  DEFAULT_HOSTS+=("$1")
  resolve_to_set "$1"
}

allow_project() {
  log "allowing $1 (project)"
  PROJECT_HOSTS+=("$1")
  resolve_to_set "$1"
}

allow_cidr() {
  log "allowing CIDR $1"
  ipset add cbox-allow "$1" 2>/dev/null || true
}

# === Default allow-list (slim) ===
allow_default api.anthropic.com
allow_default statsig.anthropic.com
allow_default sentry.io

allow_default github.com
allow_default api.github.com
allow_default objects.githubusercontent.com
allow_default codeload.github.com

# GitHub IP ranges from /meta. Best-effort — if it fails (network not yet
# fully up, or rate-limited), we still have DNS-resolved A records above.
log "fetching GitHub IP CIDRs"
if curl -fsSL --max-time 10 https://api.github.com/meta 2>/dev/null \
   | jq -r '.web[]?,.api[]?,.git[]?' 2>/dev/null \
   | sort -u > /tmp/gh-cidrs; then
  while read -r cidr; do
    [[ -n "$cidr" ]] && allow_cidr "$cidr"
  done < /tmp/gh-cidrs
else
  log "WARNING: could not fetch GitHub CIDRs (continuing with DNS-resolved A records only)"
fi

allow_default gitlab.com
allow_default registry.gitlab.com

# host.containers.internal — for talking to host services (Ollama, MCP, etc.).
if getent hosts host.containers.internal >/dev/null 2>&1; then
  allow_default host.containers.internal
fi

# === Per-project allow-list (mounted at /cbox/allowlist if present) ===
if [[ -f /cbox/allowlist ]]; then
  log "loading per-project allow-list /cbox/allowlist"
  while IFS= read -r line; do
    line="${line%%#*}"             # strip comments
    line="${line//[[:space:]]/}"   # strip whitespace
    [[ -z "$line" ]] && continue
    allow_project "$line"
  done < /cbox/allowlist
fi

# Apply: accept ipset matches, log + reject everything else.
iptables -A OUTPUT -m set --match-set cbox-allow dst -j ACCEPT
iptables -A OUTPUT -j LOG --log-prefix "cbox-firewall-blocked: " --log-level 4
iptables -A OUTPUT -j REJECT --reject-with icmp-host-unreachable

# Boot verification: anthropic reachable, example.com blocked.
log "verifying api.anthropic.com is reachable..."
if ! curl -fsS --max-time 5 -o /dev/null https://api.anthropic.com; then
  fail "api.anthropic.com unreachable after firewall init"
fi
log "verifying example.com is blocked..."
if curl -fsS --max-time 3 -o /dev/null https://example.com 2>/dev/null; then
  fail "example.com reachable; firewall did not engage"
fi

# Write the ground-truth file the agent can read.
NETFILE=/workspace/.cbox-network
log "writing $NETFILE"
{
  printf '# cbox active network allow-list\n'
  printf '# Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# This file lists the hosts the firewall accepts outbound traffic for.\n'
  printf '# All other destinations are REJECTed.\n\n'
  printf '[default]\n'
  for h in "${DEFAULT_HOSTS[@]}"; do printf '%s\n' "$h"; done
  printf 'DNS: 1.1.1.1, 8.8.8.8\n\n'
  printf '[per-project]\n'
  if [[ ${#PROJECT_HOSTS[@]} -eq 0 ]]; then
    printf '# (no per-project allow-list mounted at /cbox/allowlist)\n'
  else
    for h in "${PROJECT_HOSTS[@]}"; do printf '%s\n' "$h"; done
  fi
} > "$NETFILE"
chown agent:agent "$NETFILE" 2>/dev/null || true
chmod 0644 "$NETFILE"

log "firewall ready"
