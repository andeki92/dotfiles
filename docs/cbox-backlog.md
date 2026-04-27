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

## From security audit (2026-04-27)

Tracked in PR #41 review; not blocking the v2 merge.

15. **Per-session SSH deploy key instead of host-agent forwarding.** Currently
    `$SSH_AUTH_SOCK` is forwarded into the container, which means a compromised
    agent has full key-use rights for the duration of the session — `git push --force`
    on any repo your key authorizes, gist creation, etc. The fix: at `cbox new`, prompt
    for a per-repo deploy key (or fine-grained PAT) and forward only that. Stopgap
    documented in README: `ssh-add -t 3600 -c` for confirmation-required key use.
16. **`cbox up` should recreate the container fresh.** Currently the container persists
    across `stop`/`up`, so a one-time compromise (planted .bashrc, modified /etc, etc.)
    survives across sessions. Worktree is the durable state; rootfs should be ephemeral.
    Change `cbox up` to `engine_rm` + `engine_run_detached` unconditionally; the user
    re-pays `mise install` (already in entrypoint).
17. **`cbox doctor` checks for Squid ≥ 7.2 and apple/container ≥ latest 0.11.x.**
    CVE-2025-62168 (Squid creds disclosure, CVSS 10) was fixed in 7.2; 7.1 and earlier
    are exposed. apple/container has no published advisories yet but is pre-1.0 — keep
    on the latest patch.
18. **Pin BASE image by digest in Containerfile.** Currently `FROM debian:trixie-slim`
    floats; a registry compromise could swap the base. Replace with
    `FROM debian:trixie-slim@sha256:...` and update on `cbox build`.
19. **OAuth token: drop env-var path entirely.** v2 entrypoint writes the token to
    `~/.claude/.credentials.json` then `unset`s the env, but the var is still set at
    container creation time and visible to `container exec <name> env` (host-side).
    Cleaner: pass via per-session writable mount instead, never as -e.
20. **Plugin source secret scan.** `cbox doctor` greps `~/.claude/plugins` for
    high-entropy strings / common secret patterns and warns if a user committed
    secrets into a personal skill.
21. **Disable IPv6 egress in firewall.** `init-firewall.sh` only sets IPv4 rules;
    `ip6tables` rules should mirror them so `curl -6` doesn't bypass the proxy.
    Probably a non-issue since apple/container's vmnet is v4-only, but worth
    confirming and locking down.
