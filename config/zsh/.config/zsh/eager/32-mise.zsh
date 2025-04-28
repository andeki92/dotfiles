# mise-en-place integration for zsh
# This file is loaded eagerly by zsh

# Check if mise is installed
if command -v mise &>/dev/null; then
  # Add mise activation to the shell
  eval "$(mise activate zsh)"
  
  # Add completions
  eval "$(mise completion zsh)"
else
  echo "mise is not installed. Run 'brew install mise' to install it."
fi 