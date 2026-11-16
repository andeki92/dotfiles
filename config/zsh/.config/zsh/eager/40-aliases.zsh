# Minimal aliases file
# Only includes the most essential aliases

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# General
alias h='history'
# rl — reload by replacing the shell, not re-sourcing .zshrc on top of it:
# re-sourcing keeps aliases and functions a newer config no longer defines.
alias rl='exec zsh'

# Listing
alias l='ls -lah'
alias la='ls -lAh'
alias ll='ls -lh'

# AI agents (claude, c, oc): eager/47-ai.zsh
