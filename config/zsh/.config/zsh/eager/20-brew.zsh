# Homebrew initialization for cross-platform support
# This file initializes Homebrew for both macOS and Linux environments

# Initialize Homebrew path based on platform
if is_macos; then
  # For Apple Silicon (ARM) Macs
  if [[ -d "/opt/homebrew" ]]; then
    export HOMEBREW_PREFIX="/opt/homebrew"
  # For Intel Macs
  elif [[ -d "/usr/local/Homebrew" ]]; then
    export HOMEBREW_PREFIX="/usr/local"
  fi
elif is_linux; then
  # Standard Linux Homebrew location
  if [[ -d "/home/linuxbrew/.linuxbrew" ]]; then
    export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
  # User-specific Linuxbrew location
  elif [[ -d "$HOME/.linuxbrew" ]]; then
    export HOMEBREW_PREFIX="$HOME/.linuxbrew"
  fi
fi

# Only set up Homebrew if we found a prefix
if [[ -n "$HOMEBREW_PREFIX" ]]; then
  # Add Homebrew to PATH
  export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
  
  # Set up Homebrew environment variables
  export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
  export MANPATH="$HOMEBREW_PREFIX/share/man:$MANPATH"
  export INFOPATH="$HOMEBREW_PREFIX/share/info:$INFOPATH"
  
  # Load zsh completions if they exist
  if [[ -d "$HOMEBREW_PREFIX/share/zsh/site-functions" ]]; then
    fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
  fi
  
  # Speed up brew installation by avoiding unnecessary git status checks
  export HOMEBREW_NO_AUTO_UPDATE=1
  
  # Disable analytics
  export HOMEBREW_NO_ANALYTICS=1
fi 