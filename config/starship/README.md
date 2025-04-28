# Starship Prompt

## Overview

[Starship](https://starship.rs/) is a minimal, blazing-fast, and infinitely customizable prompt for any shell. This directory contains the configuration for Starship.

## Structure

- `.config/starship.toml`: Main configuration file for Starship

## Integration with Zsh

Starship is integrated with our Zsh configuration directly (not lazy-loaded):

```
config/zsh/.config/zsh/eager/30-starship.zsh
```

**Note:** We found that Starship doesn't work well with zsh-defer, so it's loaded directly rather than being lazy-loaded. Fortunately, Starship is designed to be very fast, so this doesn't significantly impact shell startup time.

## Customization

To customize the prompt:
1. Edit `.config/starship.toml`
2. Run `starship config` to see available options in the browser
3. Use [Starship documentation](https://starship.rs/config/) for reference

## Installation

Starship is installed via Homebrew in our setup:

```bash
brew install starship
```

Our dotfiles will automatically set up the configuration when stowed:

```bash
stow starship
``` 