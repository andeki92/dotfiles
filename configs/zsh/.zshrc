#!/usr/bin/env zsh

# Custom env
[ -f ~/.zshenv ] && source ~/.zshenv

# Custom functions
[ -f ~/.config/functions.zsh ] && source ~/.config/functions.zsh

# Custom aliases
[ -f ~/.config/aliases.zsh ] && source ~/.config/aliases.zsh

# Other zsh-configs
[ -f ~/.config/starship.zsh ] && source ~/.config/starship.zsh

# WSL specific things
if grep --quiet microsoft /proc/version 2>/dev/null; then
  # Set Windows display for WSL
  export DISPLAY=':0.0'
  export LIBGL_ALWAYS_INDIRECT=1
  export GDK_BACKEND=x11

  # Oracle Tools
  export PATH=$PATH:$HOME/.local/lib/oracle/instantclient_19_18
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/.local/lib/oracle/instantclient_19_18
  export ORACLE_HOME=$HOME/.local/lib/oracle/instantclient_19_18
  export TNS_ADMIN=~/tnsadmin

  # OCI
  export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
fi

# Preferred editor for local and remote sessions
export EDITOR='vim'

case $(uname) in
Linux)
  brew_home=/home/linuxbrew/.linuxbrew

  if service docker status 2>&1 | grep -q "is not running"; then
    wsl.exe -d "${WSL_DISTRO_NAME}" -u root -e /usr/sbin/service docker start >/dev/null 2>&1
  fi

  ;;
Darwin)
  brew_home=/opt/homebrew
  ;;
esac

if [ -d "${brew_home}" ]; then
  export PATH=${brew_home}/bin:$PATH
fi

# Go
if [[ -d /usr/local/go/bin ]]; then
  export PATH=$PATH:/usr/local/go/bin
  export PATH=$PATH:$(go env GOPATH)/bin
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ]; then
  PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi

# Rust
[ -f ~/.cargo/env ] && source ~/.cargo/env

# SDL2
if [[ -f "/opt/homebrew/bin/sdl2-config" ]]; then
  export LIBRARY_PATH="$LIBRARY_PATH:/opt/homebrew/lib"
fi

## History command configuration
HISTSIZE=5000                 # How many lines of history to keep in memory
HISTFILE=~/.zsh_history       # Where to save history to disk
SAVEHIST=5000                 # Number of history entries to save to disk
setopt extended_history       # record timestamp of command in HISTFILE
setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_dups       # ignore duplicated commands history list
setopt hist_ignore_space      # ignore commands that start with space
setopt hist_verify            # show command with history expansion to user before running it
setopt inc_append_history     # add commands to HISTFILE in order of execution
setopt share_history          # share command history data

# Starship
eval "$(starship init zsh)"

# ASDF
[ -f "$(brew --prefix asdf)/libexec/asdf.sh" ] && source "$(brew --prefix asdf)/libexec/asdf.sh"

# set JAVA_HOME on every change directory
function asdf_update_java_home {
  asdf current java 2>&1 >/dev/null
  if [[ "$?" -eq 0 ]]; then
    export JAVA_HOME=$(asdf where java)
  fi
}

precmd() { asdf_update_java_home; }
# end set JAVA_HOME

autoload -U +X bashcompinit && bashcompinit

case $(uname) in
Linux)
  # Elhub Platform Utilities
  if [ -d "$HOME/workspace/elt/platform-utils/scripts" ]; then
    PATH="$HOME/workspace/elt/platform-utils/scripts:$PATH"
  fi

  # Ensure ssh-agent is running
  eval $(keychain --eval --agents ssh id_rsa)

  # https://www.reddit.com/r/zsh/comments/sbt9zn/annoying_problem_with_starship_zsh_and_vimode/
  function zle-line-init zle-keymap-select {
    RPS1="${${KEYMAP/vicmd/-- NORMAL --}/(main|viins)/-- INSERT --}"
    RPS2=$RPS1
    zle reset-prompt
  }
  zle -N zle-line-init
  zle -N zle-keymap-select

  export SDKMAN_DIR="/home/anders.klever.kirkeby/.sdkman"
  [[ -s "/home/anders.klever.kirkeby/.sdkman/bin/sdkman-init.sh" ]] && source "/home/anders.klever.kirkeby/.sdkman/bin/sdkman-init.sh"
  source /home/anders.klever.kirkeby/.sdkman/.sdkmanshrc #THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
  ;;
esac
