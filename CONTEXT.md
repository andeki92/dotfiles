# CONTEXT.md

Shared vocabulary for this repo — the terms an agent (or a person) needs to
read the codebase and this project's own docs the same way. Read by
`wait-what`, and worth citing from other skills or docs when a term is
load-bearing.

## Vocabulary

| Term | Means |
|---|---|
| `cbox` | The Podman/apple-container sandbox an agent may run inside (`config/cbox/`); egress is locked to an allow-list via a host-side Squid proxy. |
| `cordis` | The plugin/patch loader `dsh` profiles are built from — a profile's `cordis.yml` lists bundles, its `cordis.patch.yml` overrides individual plugin rows. |
| `dsh` | DeepSeek harness — the AI coding agent configured under `config/dsh/`; profiles (e.g. `web`) compose bundles via `cordis` files. |
| `eager` / `lazy` | The two zsh load tiers under `config/zsh/.config/zsh/`: `eager/` runs synchronously at startup (numbered `NN-name.zsh`), `lazy/` is deferred with `zsh-defer` until after the prompt draws. |
| `herdr` | "Agent Multiplexer" (Brewfile's term) — a tmux-like terminal multiplexer, prefix `ctrl+a`, for running multiple coding-agent sessions in panes. |
| `llm-wiki` | `config/llm-wiki/` holds one file — a path pointer to `~/llm-wiki`, the user's personal Obsidian knowledge vault, for tools that need to locate it. |
| `opencode` | The open-source terminal AI coding agent from opencode.ai, configured under `config/opencode/`. |
| `stow` | GNU Stow, the symlink manager this whole repo is built around — turns each `config/<tool>/` tree into live files under `~` (see `.stowrc`). |
| `XDG` | The XDG Base Directory spec this repo mirrors: `config/<tool>/.config/<tool>/` becomes `~/.config/<tool>` once stowed. |

Keep it thin: define a term here only once someone would misread it without
the definition, or once it comes up more than once. A term used exactly
once in one place doesn't need an entry — define it inline instead.
