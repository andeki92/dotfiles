# Homebrew Configuration

## Overview

This directory contains configuration for [Homebrew](https://brew.sh), the missing package manager for macOS (and Linux). The configuration follows XDG Base Directory specifications and uses Brewfile for declarative package management.

## Structure

- `.config/homebrew/Brewfile` - Main Brewfile defining all packages, casks, and applications

## Homebrew Defaults

Homebrew follows the XDG Base Directory Specification for configuration:

- Global Brewfile: `${XDG_CONFIG_HOME}/homebrew/Brewfile` (defaults to `~/.config/homebrew/Brewfile`)
- When `--global` flag is used, Homebrew will use this location

## Usage

### Installing Packages

```bash
# Install all packages from global Brewfile
brew bundle --global

# Install without upgrading existing packages
brew bundle --global --no-upgrade
```

### Updating Brewfile

```bash
# Create/update global Brewfile from currently installed packages
brew bundle dump --global --force
```

### Checking Installation Status

```bash
# Check if all dependencies are installed
brew bundle check --global

# List all dependencies in the Brewfile
brew bundle list --global
```

### Cleanup

```bash
# Show what would be removed (packages not in Brewfile)
brew bundle cleanup --global

# Actually remove packages not in Brewfile
brew bundle cleanup --global --force
```

## Environment Variables

The following environment variables can be used to customize Homebrew's behavior:

- `HOMEBREW_BUNDLE_FILE`: Specify custom Brewfile location
- `HOMEBREW_BUNDLE_NO_LOCK`: Disable lockfile generation
- `HOMEBREW_BUNDLE_NO_UPGRADE`: Skip upgrading outdated packages
- `HOMEBREW_BUNDLE_BREW_SKIP`: Skip installing Homebrew formulas
- `HOMEBREW_BUNDLE_CASK_SKIP`: Skip installing Casks
- `HOMEBREW_BUNDLE_MAS_SKIP`: Skip installing Mac App Store apps
- `HOMEBREW_BUNDLE_TAP_SKIP`: Skip tapping repositories

## Useful Aliases

See `config/zsh/.config/zsh/eager/41-brew-aliases.zsh` for useful Homebrew aliases and functions.

## Customization

The Brewfile is organized into sections:

1. **Taps** - Sources for packages
2. **Development Tools** - Programming and development utilities
3. **Shells and CLI Utilities** - Command-line tools 
4. **Language Support** - Programming language environments (commented by default)
5. **Applications** - macOS applications
6. **Fonts** - Fonts for development and UI
7. **Mac App Store** - Applications from the Mac App Store (requires `mas`)

Modify the Brewfile to add or remove packages based on your needs. 
Follow the format of the existing entries, keeping comments for readability.

## Tips

- The Language Support section is commented by default. Uncomment the languages you actually use.
- Mac App Store applications require the `mas` CLI tool. Install it with `brew install mas` if needed.
- To install only part of the Brewfile, you can edit a copy and run `brew bundle` with that specific file. 