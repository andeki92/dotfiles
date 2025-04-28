# Starship Prompt Initialization
# Note: Starship doesn't work well with zsh-defer, so we load it directly

# Check if starship is installed
if (( $+commands[starship] )); then
  # Initialize starship directly
  eval "$(starship init zsh)"
else
  # Set a basic fallback prompt if starship is not installed
  PROMPT='%F{cyan}> %f'
  RPROMPT=''
  
  # Enable colors for the fallback prompt
  autoload -Uz colors && colors
  
  # Output warning about missing starship (only once at startup)
  echo "Warning: Starship is not installed. Using fallback prompt."
  echo "Install with: brew install starship"
fi 