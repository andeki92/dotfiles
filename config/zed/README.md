# zed

[Zed](https://zed.dev) editor configuration.

Stowed: `config/zed/.config/zed/` → `~/.config/zed/`.

## Tracked

| File | Purpose |
|------|---------|
| `settings.json` | Editor settings + Catppuccin theming |
| `keymap.json`   | Custom keybindings (terminal `shift-enter` → ESC+CR) |

`prompts/` (binary LMDB prompt-library DB) and `themes/` (empty; themes come
from the extension below) are local machine state — gitignored, left in place by
stow.

## Theming

Kept consistent with the rest of the setup — Catppuccin **Macchiato** (dark) /
**Latte** (light), matching ghostty, starship, and nvim. Both flavors are
applied via system appearance, mirroring ghostty's `light:latte / dark:macchiato`
auto-switch.

The theme and icon theme ship as Zed extensions, declared for auto-install in
`settings.json`:

```jsonc
"auto_install_extensions": { "catppuccin": true, "catppuccin-icons": true }
```

Zed installs them on next launch (needs network the first time). No theme files
are vendored — see [Catppuccin for Zed](https://github.com/catppuccin/zed).

## Note: JSONC and the lint hook

Zed's `settings.json` / `keymap.json` are **JSONC** (comments + trailing commas).
The global Claude Code JSON lint hook
(`config/claude/.claude/hooks/linters/json.sh`) is JSONC-aware, so editing these
files won't raise false "invalid JSON" errors.

## Apply

```bash
stow zed
```

If `~/.config/zed/settings.json` or `keymap.json` already exist as real files,
remove them first (back them up) so stow can create the symlinks.
