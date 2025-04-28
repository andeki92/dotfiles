# Minimal completion configuration

# Load and initialize the completion system
autoload -Uz compinit
compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"

# Cache directory
if [[ ! -d "$XDG_CACHE_HOME/zsh" ]]; then
  mkdir -p "$XDG_CACHE_HOME/zsh"
fi

# Basic completion settings
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# Enable caching
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache" 
