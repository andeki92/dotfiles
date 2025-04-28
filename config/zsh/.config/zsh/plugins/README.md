# Zsh Plugins

## Overview

This directory contains plugins for Zsh. We use git submodules for plugin management to ensure maintainability and easy updates.

## Current Plugins

### zsh-defer

[zsh-defer](https://github.com/romkatv/zsh-defer) is used for lazy loading other plugins and heavy configurations. This ensures a fast shell startup time.

Located at:
- `zsh-defer-sub/` (git submodule)

## Usage

### Adding a New Plugin

To add a new plugin as a submodule:

```bash
git submodule add https://github.com/username/plugin-name.git config/zsh/.config/zsh/plugins/plugin-name
```

### Updating Plugins

To update all plugins:

```bash
git submodule update --remote
```

To update a specific plugin:

```bash
git submodule update --remote config/zsh/.config/zsh/plugins/plugin-name
```

## Loading Order

Plugins are loaded according to our numeric prefix convention:

1. `zsh-defer` is loaded eagerly in `config/zsh/.config/zsh/eager/15-defer.zsh`
2. Other plugins are loaded lazily using zsh-defer in the `lazy/` directory

## Best Practices

- Use zsh-defer for heavy plugins to ensure fast shell startup
- Keep plugin configuration separate from plugin loading
- Document plugin usage and configuration in comments
- Use git submodules for all third-party plugins 