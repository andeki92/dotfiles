#!/usr/bin/env bash
# cbox in-VM firewall — applied once at session start by `cbox` via
# `container exec --user root`. Forces all egress through the host-side
# Squid proxy. Closes the non-HTTP bypass (ICMP, raw TCP, plain DNS, ssh,
# etc.) that an HTTP-only proxy can't see.
#
# What this allows:
#   - loopback (anything inside the container talking to itself)
#   - established/related (so we get reply packets for connections we
#     already initiated through the proxy)
#   - DNS (UDP+TCP/53) to whatever resolver /etc/resolv.conf points at
#     (apple/container injects the vmnet gateway, e.g. 192.168.64.1)
#   - TCP to the host-side Squid: 192.168.64.1:3128 (apple/container
#     vmnet host gateway) — adjust if vmnet subnet differs
#
# Everything else: REJECT with icmp-port-unreachable so the agent gets
# a fast clear failure ("Connection refused") rather than hanging.
#
# Re-run safe: flushes existing rules first.

set -euo pipefail
IFS=$'\n\t'

readonly PROXY_HOST="${CBOX_PROXY_HOST:-192.168.64.1}"
readonly PROXY_PORT="${CBOX_PROXY_PORT:-3128}"

log() { printf '[firewall] %s\n' "$*" >&2; }

[[ "$(id -u)" == 0 ]] || { log "must be root"; exit 1; }
command -v iptables >/dev/null || { log "iptables missing in image"; exit 1; }

log "applying egress allow-list (proxy=${PROXY_HOST}:${PROXY_PORT})"

iptables -F OUTPUT
iptables -F INPUT
iptables -P OUTPUT ACCEPT  # we'll switch to REJECT-everything-not-matched at the end
iptables -P INPUT  ACCEPT

# Loopback — always allow.
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT

# Established/related on input so reply packets work.
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# DNS to whatever /etc/resolv.conf says (apple/container's vmnet gateway).
declare -a resolvers=()
if [[ -r /etc/resolv.conf ]]; then
  while read -r kw addr _; do
    [[ "$kw" == "nameserver" && -n "$addr" ]] && resolvers+=("$addr")
  done < /etc/resolv.conf
fi
# Fallback if /etc/resolv.conf was somehow empty.
[[ ${#resolvers[@]} -eq 0 ]] && resolvers+=("$PROXY_HOST")
for r in "${resolvers[@]}"; do
  log "  allow DNS → $r"
  iptables -A OUTPUT -p udp --dport 53 -d "$r" -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 53 -d "$r" -j ACCEPT
done

# TCP to the host-side Squid proxy.
log "  allow TCP → ${PROXY_HOST}:${PROXY_PORT}"
iptables -A OUTPUT -p tcp -d "$PROXY_HOST" --dport "$PROXY_PORT" -j ACCEPT

# Accept replies for connections we initiated.
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Everything else: deny. Use REJECT (not DROP) so the agent gets a fast
# "Connection refused" instead of a 30-second timeout, which makes
# allow-list misconfiguration much easier to diagnose.
iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable

# Verification probe.
log "verification: anthropic via proxy should work"
if curl -s --max-time 5 -o /dev/null -w '%{http_code}' \
     -x "http://${PROXY_HOST}:${PROXY_PORT}" https://api.anthropic.com \
     | grep -qE '^[2345][0-9][0-9]$'; then
  log "  ✓ proxy reachable"
else
  log "  ! proxy unreachable — check that Squid is up on host"
fi
log "verification: direct ping should be blocked"
if ! ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
  log "  ✓ direct egress blocked"
else
  log "  ! direct egress NOT blocked — firewall did not engage correctly"
fi

log "firewall ready"
