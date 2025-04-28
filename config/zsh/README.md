# Zsh Configuration

This directory contains our Zsh configuration, structured according to our modular, XDG-compliant approach.

## Structure

The configuration is organized by numeric prefixes to control loading order:

| Range | Purpose | Examples |
|-------|---------|----------|
| 00-09 | Core/Platform/Loaders | 01-platform.zsh, 02-defer.zsh |
| 10-19 | Prompt & Basic Shell UI | 10-base-prompt.zsh, 11-starship.zsh |
| 20-29 | Core Tools & Utilities | 20-brew.zsh, 21-fzf.zsh |
| 40-49 | Aliases & Functions | 40-aliases.zsh, 42-git-aliases.zsh |
| 50-59 | Lazy-loaded Completions | 50-zsh-completion.zsh, 51-fzf.zsh |

## Key Features

### FZF Integration (21-fzf.zsh, 51-fzf.zsh)

Our FZF configuration is split into two parts:

1. **Core Setup (21-fzf.zsh)**:
   - Environment variables for default options
   - File finding commands using fd or find
   - Preview capabilities
   - Essential productivity functions
   - Key bindings

2. **Advanced Features (51-fzf.zsh)**:
   - Extended file operations
   - Git integration
   - Docker container management
   - Package.json scripts runner
   - Search and replace function
   - Cheatsheets and man page browser

#### Highlight Functions

**File/Directory Navigation:**
- `fe`: Open files in editor
- `fcd`: Change to selected directory
- `fif`: Find in files (requires ripgrep)
- `fproj`: Project directory switcher

**Git Operations:**
- `fgc`: Git commit browser
- `fbr`: Git branch browser and checkout

**System Operations:**
- `fkill`: Process killer
- `fdoc`: Docker container management
- `fnpm`: NPM scripts runner

## Usage

Key bindings included:
- `Ctrl+G`: Git status/file browser
- `Alt+P`: Project directory switcher
- `Alt+F`: Find in files

## Dependencies

The FZF configuration relies on several tools for optimal functionality:

- [fzf](https://github.com/junegunn/fzf): The core fuzzy finder
- [fd](https://github.com/sharkdp/fd): Faster alternative to find
- [ripgrep](https://github.com/BurntSushi/ripgrep): Fast file searching
- [bat](https://github.com/sharkdp/bat): Syntax-highlighted file previews
- [jq](https://stedolan.github.io/jq/): JSON processor for some functions

All these dependencies are included in our Brewfile.

## Stow Ignore for Markdown
To prevent stow from symlinking markdown files (like this README), add the following to your `.stowrc`:

```
--ignore=README.md
--ignore=*.md
```

## References
- [zsh-defer](https://github.com/romkatv/zsh-defer)
- [zsh XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
- [zsh startup optimization](https://zsh.sourceforge.io/Doc/Release/Options.html) 