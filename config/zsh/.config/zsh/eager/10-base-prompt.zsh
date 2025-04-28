# Basic prompt configuration
# This sets a minimal prompt that will be displayed until Starship is loaded

# Set a minimal initial prompt that will be replaced by Starship
# We use a very simple prompt to avoid conflicts
PROMPT='%F{cyan}> %f'

# For right prompt, leave empty initially
RPROMPT=''

# Enable colors for the basic prompt
autoload -Uz colors && colors 