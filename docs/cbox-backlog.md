# cbox — Backlog

Items deferred from v2 (`config/cbox/`).

## Deferred from v1 (still relevant)

1. **Per-owner git push allow-list.** Pre-push hook + `~/.config/cbox/allowlist-owners.txt`.
   Discussed and deferred 2026-04-26 — needs threat-model revisit first.
2. **Fine-grained GitHub PAT instead of forwarded ssh-agent.** Strongest enforcement of push scope.
3. **`cbox upgrade`.** Wraps `cbox build --pull` + Claude version bump.
4. **`cbox cd <id>` host-side helper.** Cd to the worktree path on the host.
5. **Userspace VPN inside container.** Opt-in `cbox --vpn` flag using `tailscale` userspace mode.
6. **Multi-container pods.** When you want Claude + a sidecar (MCP server, local model).
7. **Zed remote attach.** Document Zed's SSH remote dev mode.
8. **State pruning automation.** `cbox prune --auto` scheduled via launchd/systemd.
9. **Image rebuild automation.** Weekly rebuild for security patches.
10. **Threat-model revisit.** Document an explicit threat-model matrix.
11. **Notification on long-running session.** Hook Claude's `Notification` event from inside container.

## New in v2

12. **Squid SSL-bumping (TLS-terminating MITM) as opt-in.** For per-URL filtering (not just hostname).
    Requires CA distribution to the container. Trade-off: breaks TLS-pinned clients.
13. **Per-session proxy auth.** Each session presents a token; Squid scopes allow-list per token.
    Avoids "session A's allow-list bleeds to session B."
14. **Linux microVM path** (Lima or systemd-vmspawn) as opt-in. For Linux users who want
    VM-strength FS isolation matching the macOS path.
