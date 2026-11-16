# Zsh Configuration

## Structure

This Zsh configuration follows a modular structure with eager and lazy loading:

- `eager/`: Files loaded at shell startup (performance-critical)  
- `lazy/`: Files loaded after the prompt appears (deferred)
- `plugins/`: External plugins and tools

## Features

### Package Management & Updates

A reminder system is included that periodically checks when you last updated your package managers. It:

- Shows reminders when updates are due (default: every 3 days)
- Provides convenient update commands
- Tracks when updates were last performed
- Runs after your prompt appears (doesn't slow down startup)

#### Update Commands

| Command | Description |
|---------|-------------|
| `update_brew` | Update Homebrew and all packages |
| `update_mise` | Update mise-en-place and managed tools |
| `update_all` | Update everything |

#### Aliases

| Alias | Command |
|-------|---------|
| `brewup` | Update Homebrew |
| `miseup` | Update mise |
| `updateall` | Update everything |

#### Configuration

You can customize the reminder frequency by setting `UPDATE_REMINDER_DAYS` in your `.zshrc` or another config file before this module loads.

### Package Managers

- **Homebrew**: Managed in eager loading for core functionality
- **mise-en-place**: activated eagerly (`eager/50-mise.zsh`), so tools are on PATH before the first prompt

## Loading Order

1. Core system, environment variables and helpers (eager)
2. Package managers & version managers (eager)
3. Aliases, tool functions and the prompt (eager)
4. Completions, fzf integration & heavier functions (lazy, deferred with zsh-defer)

### Cached init scripts

`eager/16-cached-init.zsh` defines `_cached_init`, which keeps the output of an
init command (`starship init`, `fzf --zsh`) under `$XDG_CACHE_HOME/zsh/init/`
and regenerates it when the command's binary resolves to a different file.
Delete that directory to force a refresh.

## PATH Management

To prevent PATH duplication when reloading the shell configuration (`source ~/.zshrc`), we use zsh's `-U` flag with the `path` array, which automatically enforces uniqueness:

```zsh
# In 10-platform.zsh
typeset -U path
```

This approach:
1. Uses zsh's `path` array which automatically maps to the `PATH` environment variable
2. The `-U` flag ensures only unique elements are kept in the array
3. When adding to PATH, we use the array syntax: `path=(/new/path $path)`
This pattern prevents PATH from growing with duplicates when the configuration is sourced again.

To reload, use `rl` (`exec zsh`): it starts a fresh shell, so aliases and
functions that a newer config no longer defines don't linger.
