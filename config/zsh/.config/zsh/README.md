# Zsh Configuration

## Structure

This Zsh configuration follows a modular structure with eager and lazy loading:

- `eager/`: Files loaded at shell startup (performance-critical)  
- `lazy/`: Files loaded after the prompt appears (deferred)
- `plugins/`: External plugins and tools

## Features

### Package Management & Updates

A reminder system is included that periodically checks when you last updated your package managers. It:

- Shows reminders when updates are due (default: every 7 days)
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
- **mise-en-place**: Lazily loaded to improve shell startup time

## Loading Order

1. Core system & environment variables (eager)
2. Prompt & basic interactivity (eager)
3. Package managers & version managers (lazy)
4. Completions & enhanced features (lazy)
5. Aliases & user customizations (lazy)

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
4. The reload alias also reinforces uniqueness: `alias rl='typeset -U path && source ~/.zshrc'`

This pattern prevents PATH from growing with duplicates when reloading the shell configuration multiple times. 