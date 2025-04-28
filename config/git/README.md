# Git Configuration

This directory contains XDG-compliant git configuration files for use with GNU Stow.

## Structure
- `.config/git/config` → `~/.config/git/config`

## Settings
- `[user]` section sets your name and email for commits
- `[push] default = current` enables automatic push of the current branch
- `[init] defaultBranch = main` sets the default branch name to `main` for new repositories

## Usage
Stow this package to symlink the configuration:

```bash
stow git
``` 