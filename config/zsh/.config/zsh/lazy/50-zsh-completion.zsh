# Zsh completion configuration
# Properly deferred for faster shell startup

# Define a function for completion setup
_setup_completion() {
  # Cache directory
  if [[ ! -d "$XDG_CACHE_HOME/zsh" ]]; then
    mkdir -p "$XDG_CACHE_HOME/zsh"
  fi

  # Load and initialize the completion system
  autoload -Uz compinit
  compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"

  # Basic completion settings
  zstyle ':completion:*' menu select
  zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

  # Enable caching
  zstyle ':completion:*' use-cache on
  zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
}

# Defer the completion setup
# This will run after the prompt appears
zsh-defer _setup_completion 
