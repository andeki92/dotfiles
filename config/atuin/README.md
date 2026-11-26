# atuin — local shell & agent command history

Stowed to `~/.config/atuin/`. Installed via `config/mise/.config/mise/config.toml` (`atuin = "18.25.1"`).

Configured strictly for **local mode**:
- `auto_sync = false` (no cloud or server sync)
- `[daemon] enabled = false`, `autostart = false`
- `[threads] enabled = false` (no session/transcript capture)
- `secrets_filter = true`

`config/zsh/.zshenv` exports `ATUIN_CONFIG_DIR="$XDG_CONFIG_HOME/atuin"` so Atuin 18.25+ always reads `~/.config/atuin/config.toml` rather than generating a separate `~/.atuin/config.toml`.

Shell integration loads lazily via `config/zsh/.config/zsh/lazy/53-atuin.zsh` (using `_cached_init`, with `--disable-up-arrow` so Up-Arrow stays native while `Ctrl+R` opens Atuin).

## Pi agent history hook

Installed by `./scripts/pi-bootstrap.sh` via:

```bash
atuin setup --only --agent-history --agents pi --no-threads --no-daemon --no-mcp --sync off
```

This writes `~/.pi/agent/extensions/atuin.ts` so commands run by Pi's `bash` tool are recorded with `author = "pi"` (hidden from interactive `Ctrl+R` by default, queryable with `atuin search --author pi -- ''`).
