# Zsh completion configuration
# Properly deferred for faster shell startup

# Define a function for completion setup
_setup_completion() {
  # Cache directory
  if [[ ! -d "$XDG_CACHE_HOME/zsh" ]]; then
    mkdir -p "$XDG_CACHE_HOME/zsh"
  fi

  # Vendored completions (completions/README.md), ahead of compinit
  fpath=("$XDG_CONFIG_HOME/zsh/completions" $fpath)

  # Load and initialize the completion system
  # Full compinit (which looks for new completion files and insecure
  # directories) at most once a day; -C trusts the dump otherwise, 21ms -> 4ms.
  # A new completion shows up within a day, or at once after: rm "$dump".
  # touch, because compinit rewrites the dump only when something changed.
  autoload -Uz compinit
  local dump="$XDG_CACHE_HOME/zsh/zcompdump"
  local -a fresh=( $dump(N.mh-24) )
  if (( $#fresh )); then
    compinit -C -d "$dump"
  else
    compinit -d "$dump" && touch "$dump"
  fi

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
