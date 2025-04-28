# mise-en-place integration for zsh
# This file is loaded lazily using zsh-defer

# Check if mise is installed and defer the activation
if command -v mise &>/dev/null; then
  # Use zsh-defer to load mise after shell startup
  zsh-defer eval "$(mise activate zsh)"
  
  # Also defer completion loading
  zsh-defer eval "$(mise completion zsh)"
else
  # Even the error message is deferred to not slow down startup
  zsh-defer echo "mise is not installed. Run 'brew install mise' to install it."
fi 