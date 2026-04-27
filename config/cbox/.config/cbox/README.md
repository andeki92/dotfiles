# cbox — Code Sandbox

Portable, dotfile-managed sandbox for running Claude Code (and other coding
agents) inside a per-session container with a host-side egress allow-list.

- macOS: `apple/container` per-VM isolation. Linux: rootful Podman.
- Egress filtered by a host-side Squid proxy in CONNECT-only mode.
- Per-session git worktree at `~/.cbox/worktrees/<repo>-<id>/`, owned by tmux.
- Credentials (ssh-agent, gpg-agent, ~/.gitconfig, ~/.claude) mounted r/o or
  via socket forwarding — no key bytes ever enter the container.

## Quick start

```bash
cbox doctor          # check the host
cbox build           # build cbox:latest (first time only)
cd ~/code/some-repo
cbox                 # spawn a new sandboxed Claude session
```

## Commands

| Command | Behavior |
|---|---|
| `cbox` | New sandboxed Claude session in CWD (must be a git repo). |
| `cbox ls` | List active sessions. |
| `cbox attach [<id>]` | Reattach (fzf if no id). |
| `cbox stop [<id>]` | Stop container + tmux. Worktree preserved. |
| `cbox up <id>` | Restart against an existing worktree. |
| `cbox rm [<id>] [-f]` | Remove worktree + delete branch if no upstream. |
| `cbox prune [--apply]` | Remove sessions whose tmux is gone. |
| `cbox doctor` | Diagnose host health. |
| `cbox build` | Rebuild cbox:latest for the active engine. |
| `cbox proxy {start,stop,status,reload}` | Manage the Squid proxy. |

## Layout

| Path | Purpose |
|---|---|
| `~/.config/cbox/Containerfile` | The image |
| `~/.config/cbox/entrypoint.sh` | Container entry: mise install + exec |
| `~/.config/cbox/squid.conf.template` | Squid base config |
| `~/.config/cbox/allowlist.d/_default.txt` | Default egress allow-list |
| `~/.config/cbox/allowlist.d/<repo>.txt` | Per-project allow-list |
| `~/.config/cbox/env.d/<name>.env(.sops)` | Env vars (sops-encrypted by default) |
| `~/.local/bin/cbox` | The wrapper script |
| `~/.local/share/cbox/lib/*` | Sourced lib files |
| `~/.cbox/worktrees/<repo>-<id>/` | Per-session worktree (NOT in dotfiles) |
| `~/.cbox/state/sessions.json` | Live-session record |
| `~/.cbox/state/squid.{conf,pid,log}` | Squid runtime state |

## Per-project config

Optional `.cbox.toml` at the repo root:

```toml
[firewall]
allow = ["developers.strava.com"]   # added to Squid allow-list for this session

[env]
files = ["default", "homelab"]      # which env.d/*.env files to load

[mise]
install = true                      # default true; opt out for non-mise projects

[mounts]
extra = []                          # ["~/.aws/config:/home/agent/.aws/config:ro"]
```

## Recovery / troubleshooting

- `cbox doctor` first.
- Container exited but worktree remains: `cbox up <id>`.
- Worktree corrupt: `cbox rm <id> --force`, then start fresh.
- Squid won't start: check `~/.cbox/state/squid.log`.
- Container can't reach the proxy: verify `host.containers.internal` resolves
  inside the VM; if not, the proxy host needs to be the vmnet gateway IP.

## Threat model (TL;DR)

cbox restricts the blast radius of `rm -rf` and `curl evil.com`, but it cannot
restrict `git push --force` or `gh gist create` — both are explicitly enabled.
Use branch protection on remotes; never target `main` from inside cbox.
