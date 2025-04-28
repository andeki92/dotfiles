# mise-en-place

## Overview
This module contains configuration for [mise-en-place](https://mise.jdx.dev/), a fast and extensible tool version manager that replaces tools like nvm, pyenv, rbenv, etc.

## Structure
- `.config/mise/config.toml` - Global configuration for mise

## Features
- **Unified version management** for multiple programming languages and tools
- **Configurable aliases** for easy version switching
- **Per-project versioning** via .mise.toml files
- **Legacy version file support** for compatibility with .nvmrc, .python-version, etc.

## Installation

```bash
# Install mise
brew install mise

# Stow this configuration
stow mise
```

## Shell Integration

Add this to your `.zshrc` or similar:

```bash
# Initialize mise
eval "$(mise activate zsh)"

# For completions (optional)
eval "$(mise completion zsh)"
```

## Usage

```bash
# Install and use a specific version of a tool
mise use node@18
mise use python@3.12

# Create a project-specific configuration
cd /path/to/your/project
mise init

# Install all tools specified in the current directory
mise install

# Run a command with specific tool versions
mise run -- npm test

# Show currently activated versions
mise current
```

## Migration from Other Tools

If you are migrating from other version managers:

- From nvm: `mise use -g node@$(nvm current)`
- From asdf: `mise use -g $(cat ~/.tool-versions)`
- From pyenv: `mise use -g python@$(pyenv version-name)`

## Documentation
For more information, see the [mise documentation](https://mise.jdx.dev/). 