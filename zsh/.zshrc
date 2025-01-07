#!/usr/bin/env zsh

# inline this into .zshrc for clarity - this must be loaded
source ~/.config/zsh/plugins/zsh-defer/zsh-defer.plugin.zsh

source "${HOME}/.config/zsh/no_defer.zsh"

zsh-defer source "${HOME}/.config/zsh/defer.zsh"
zsh-defer function source
