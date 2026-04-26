# mise-en-place integration for zsh
# Load critical PATH integration immediately, defer completions

# Check if mise is installed
if command -v mise &>/dev/null; then
  # Critical: Use eval directly for mise activation to ensure proper PATH setup
  eval "$(mise activate zsh)"
  
  # Defer only the completion loading as it's not critical for functionality
  zsh-defer eval "$(mise completion zsh)"
else
  # Even the error message is deferred to not slow down startup
  zsh-defer echo "mise is not installed. Run 'brew install mise' to install it."
fi 