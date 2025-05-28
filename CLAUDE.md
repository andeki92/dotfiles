# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🚨 MANDATORY RULES - YOU MUST FOLLOW THESE 🚨

**YOU MUST manage this dotfiles repository using GNU Stow with XDG Base Directory specifications.**

### YOU MUST:
- **ALWAYS** use `stow -R .` after making configuration changes
- **ALWAYS** test zsh performance with `./scripts/benchmark.sh` before committing zsh changes
- **ALWAYS** place new configurations under `config/<tool>/` following XDG spec
- **ALWAYS** use the exact Homebrew commands specified below for package management
- **ALWAYS** check existing module README.md files before making changes

### YOU MUST NEVER:
- **NEVER** modify files directly in `~/.config/` - edit source files in `config/` instead
- **NEVER** commit zsh changes that cause >25% performance regression
- **NEVER** create configurations outside the `config/` directory structure
- **NEVER** use `brew install` directly - update the Brewfile instead
- **NEVER** ignore stow conflicts - resolve them properly

## COMMANDS YOU WILL USE

```bash
# Apply all configurations
stow .

# Apply specific tool configurations
stow zsh git brew

# Re-apply after making changes (restow)
stow -R .

# Remove symlinks (before major changes)
stow -D .

# Homebrew package management
brew bundle --global                    # Install all from Brewfile
brew bundle dump --global --force      # Update Brewfile from installed
brew bundle check --global             # Verify installation status
brew bundle cleanup --global --force   # Remove packages not in Brewfile

# Performance testing (MANDATORY for zsh changes)
./scripts/benchmark.sh                 # Test startup time
./scripts/benchmark.sh --save          # Save results to docs/benchmarks.md

# Git submodule management
git submodule update --init --recursive
```

## ARCHITECTURE - UNDERSTAND THIS STRUCTURE

### Stow Configuration Pattern
```
.dotfiles/
├── .stowrc              # Configures stow: --dir=./config --target=~/
├── config/              # Source directory for all configurations
│   ├── zsh/            # Goes to ~/.config/zsh/ and ~/.zshrc
│   ├── git/            # Goes to ~/.config/git/
│   └── <tool>/         # Each tool has its own module
└── scripts/            # Helper scripts
```

### Zsh Performance Architecture
**CRITICAL:** Zsh config uses eager/lazy loading pattern for performance:
- `config/zsh/.config/zsh/eager/` - Core config (numbered, loaded immediately)
- `config/zsh/.config/zsh/lazy/` - Heavy plugins (deferred with zsh-defer)
- Load order: eager files → lazy files → aliases

## WORKFLOWS YOU MUST FOLLOW

### Adding New Tool Configuration
1. **CREATE:** `config/<tool>/` directory
2. **STRUCTURE:** Follow XDG pattern: `config/<tool>/.config/<tool>/`
3. **TEST:** `stow <tool>` to verify symlink creation
4. **DOCUMENT:** Add brief README.md if complex

### Modifying Zsh Configuration
1. **FIRST:** Run `./scripts/benchmark.sh` for baseline
2. **EDIT:** Files in `config/zsh/.config/zsh/`
3. **APPLY:** `stow -R zsh`
4. **TEST:** `./scripts/benchmark.sh` - ensure <25% regression
5. **COMMIT:** Include benchmark results if significant change

### Managing Homebrew Packages
1. **CHECK:** `brew bundle check --global`
2. **ADD:** Edit `config/brew/.config/homebrew/Brewfile` directly
3. **INSTALL:** `brew bundle --global`
4. **VERIFY:** `brew bundle check --global`

### Performance Optimization (Zsh)
1. **PROFILE:** Add `zmodload zsh/zprof` to test slow sections
2. **DEFER:** Move heavy config to `lazy/` directory
3. **BENCHMARK:** `./scripts/benchmark.sh` after each change
4. **DOCUMENT:** Update `docs/benchmarks.md` with `--save` flag

## KEY FILES YOU MUST UNDERSTAND

**CRITICAL CONFIGURATION FILES:**
- `.stowrc` - Stow behavior: uses `./config` as source, `~/` as target
- `config/zsh/.zshrc` - Main zsh entrypoint, loads all config in order
- `config/brew/.config/homebrew/Brewfile` - Declarative package management
- `scripts/benchmark.sh` - Performance testing (mandatory for zsh changes)

**WHEN working on zsh:** ALWAYS check performance impact
**WHEN adding packages:** ALWAYS use Brewfile, never direct brew install
**WHEN stowing fails:** CHECK for existing files/conflicts in target

## TESTING REQUIREMENTS

**YOU MUST test every configuration change:**

```bash
# For any config changes
stow -R .                    # Verify stow works without conflicts

# For zsh changes (MANDATORY)
./scripts/benchmark.sh       # Must not regress >25%

# For brew changes
brew bundle check --global  # Verify all packages install correctly

# For git changes
git config --list           # Verify settings applied correctly
```

## CODE STYLE - FOLLOW EXACTLY

### Zsh Configuration Pattern
```bash
# YOU MUST number eager-loaded files
# config/zsh/.config/zsh/eager/10-core.zsh
# config/zsh/.config/zsh/eager/20-history.zsh

# YOU MUST use zsh-defer for heavy operations
# config/zsh/.config/zsh/lazy/plugins.zsh
zsh-defer source "${XDG_CONFIG_HOME}/zsh/plugins/heavy-plugin/plugin.zsh"
```

### Brewfile Organization
```ruby
# YOU MUST organize Brewfile in sections with comments
# Taps
tap "homebrew/cask"

# Development Tools  
brew "git"
brew "stow"

# Applications
cask "ghostty"
```

### File Organization Rules
- **ALWAYS** place configs in `config/<tool>/.config/<tool>/`
- **ALWAYS** use numbered prefixes for zsh eager files (10-, 20-, etc.)
- **ALWAYS** add README.md for complex tool configurations
- **NEVER** create files directly in project root

## ANTI-PATTERNS - NEVER DO THESE

**NEVER:**
- Edit `~/.zshrc` or `~/.config/*` directly - always edit source in `config/`
- Use `cd ~; stow .dotfiles` - the .stowrc handles paths correctly
- Commit Homebrew lockfiles or cache files
- Add synchronous operations to zsh eager loading
- Create configs outside the `config/` directory structure
- Ignore benchmark results showing performance regression
- Use `brew install` without updating the Brewfile
- Modify existing configs without testing stow re-application

## CI/CD INTEGRATION

**UNDERSTAND:** GitHub Actions automatically benchmark zsh changes:
- Triggers on PRs affecting `config/zsh/**`
- Compares PR branch vs main branch performance  
- **FAILS CI** if >25% performance regression
- Comments results on PR with benchmark history

**WHEN zsh PR fails CI:** Check benchmark output and optimize before merge