# Minimal .zshrc
# Loads eager and lazy configs from XDG-compliant dotfiles structure

# XDG Base Directory Specification
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Source eager configs first, then lazy configs
if [[ -d "$XDG_CONFIG_HOME/zsh/eager" ]]; then
  for config_file in "$XDG_CONFIG_HOME/zsh/eager"/*.zsh(N); do
    source "$config_file"
  done
fi
if [[ -d "$XDG_CONFIG_HOME/zsh/lazy" ]]; then
  for config_file in "$XDG_CONFIG_HOME/zsh/lazy"/*.zsh(N); do
    source "$config_file"
  done
fi
