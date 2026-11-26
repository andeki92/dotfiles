# atuin — local shell & agent command history

Stowed to `~/.config/atuin/`. Installed via `config/mise/.config/mise/config.toml` (`atuin = "18.25.1"`).

Configured strictly for **local mode**:
- `auto_sync = false` (no cloud or server sync)
- `[daemon] enabled = false`, `autostart = false`
- `[threads] enabled = false` (no session/transcript capture)
- `secrets_filter = true`

`config/zsh/.zshenv` exports `ATUIN_CONFIG_DIR="$XDG_CONFIG_HOME/atuin"` so Atuin 18.25+ always reads `~/.config/atuin/config.toml` rather than generating a separate `~/.atuin/config.toml`.

Shell integration loads lazily via `config/zsh/.config/zsh/lazy/53-atuin.zsh` (using `_cached_init`, with `--disable-up-arrow` so Up-Arrow stays native while `Ctrl+R` opens Atuin).

## Agent history hooks (Pi)

Atuin owns wiring its agent-history hook into Pi (the Pi setup itself stays Atuin-agnostic). After stowing `atuin` and installing Pi, run:

```bash
./scripts/atuin-setup.sh
```

This runs:

```bash
atuin setup --only --agent-history --agents pi --no-threads --no-daemon --no-mcp --sync off
```

It writes `~/.pi/agent/extensions/atuin.ts`, which observes Pi's `bash` tool events (compatible with the Gondolin sandbox) and records commands under `author = "pi"` while keeping sync, daemon, MCP, and Threads off.

Agent-run commands are hidden from interactive `Ctrl+R` by default. Query them explicitly with:

```bash
# List Pi-authored commands
ATUIN_SESSION=report atuin search --filter-mode global --author pi -- ''

# Count Pi-authored commands
ATUIN_SESSION=report atuin search --filter-mode global --author pi --format '{time}' -- '' | wc -l
```
