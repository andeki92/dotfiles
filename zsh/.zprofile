# Explanation of what this files does and when it is loaded
# https://apple.stackexchange.com/questions/388622/zsh-zprofile-zshrc-zlogin-what-goes-where

# XDG
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# ## History command configuration
# HISTSIZE=5000                 # How many lines of history to keep in memory
# HISTFILE=~/.zsh_history       # Where to save history to disk
# SAVEHIST=5000                 # Number of history entries to save to disk
# setopt extended_history       # record timestamp of command in HISTFILE
# setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
# setopt hist_ignore_dups       # ignore duplicated commands history list
# setopt hist_ignore_space      # ignore commands that start with space
# setopt hist_verify            # show command with history expansion to user before running it
# setopt inc_append_history     # add commands to HISTFILE in order of execution
# setopt share_history          # share command history data

# Preferred editor for local and remote sessions
export EDITOR='vim'

# https://github.com/keybase/keybase-issues/issues/2798
export GPG_TTY=$(tty)

# Krew (k8s plugin manager)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# .local binaries
export PATH=$HOME/.local/bin:$PATH

# support x11 forwarding
export DISPLAY=":0.0"
export LIBGL_ALWAYS_INDIRECT=1

# Check if the script is running in WSL2 and on Ubuntu 24.04
if grep -qE "(microsoft|WSL2)" /proc/version && grep -q "Ubuntu 24.04" /etc/os-release; then
    export TERM="screen-256color"

    # add code to path
    export PATH=$PATH:"/mnt/c/Users/anderski1/AppData/Local/Programs/Microsoft VS Code/bin/"

    # add platform-utils to path
    export PATH="$HOME/workspace/plat-platform-utils/scripts:$PATH"
    export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
fi
