# Path settings
# This file manages PATH environment variable

# Homebrew location for Apple Silicon
export HOMEBREW_PREFIX="/opt/homebrew"

# Add Homebrew to PATH
if [[ -d "$HOMEBREW_PREFIX" ]]; then
  export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
  export MANPATH="$HOMEBREW_PREFIX/share/man:$MANPATH"
  export INFOPATH="$HOMEBREW_PREFIX/share/info:$INFOPATH"
  export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
fi

# Add user's private bin if it exists
if [[ -d "$HOME/.local/bin" ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# Add user's private sbin if it exists
if [[ -d "$HOME/.local/sbin" ]]; then
  export PATH="$HOME/.local/sbin:$PATH"
fi 