# Starship Prompt

## Overview

[Starship](https://starship.rs/) is a minimal, blazing-fast, and infinitely customizable prompt for any shell. This directory contains the configuration for Starship.

## Structure

- `.config/starship.toml`: Main configuration file for Starship

## Integration with Zsh

`config/zsh/.config/zsh/eager/55-starship.zsh` loads Starship eagerly, since
it draws the first prompt and can't wait for zsh-defer. It sources the
output of `starship init zsh --print-full-init` from a cache
(`eager/16-cached-init.zsh`), regenerated when the starship binary changes,
so startup doesn't fork starship to get it.

## Customization

To customize the prompt:
1. Edit `.config/starship.toml`
2. Run `starship config` to see available options in the browser
3. Use [Starship documentation](https://starship.rs/config/) for reference

## Installation

Starship is installed by mise (`config/mise/.config/mise/config.toml`).

Our dotfiles will automatically set up the configuration when stowed:

```bash
stow starship
``` 