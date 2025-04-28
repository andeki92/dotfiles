# Minimal .zshrc
# This file is deliberately minimalist to establish a baseline for benchmarking

# XDG Base Directory Specification
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Source configuration files from XDG directory
if [[ -d "$XDG_CONFIG_HOME/zsh" ]]; then
  for config_file in "$XDG_CONFIG_HOME/zsh"/*.zsh; do
    if [[ -f "$config_file" ]]; then
      source "$config_file"
    fi
  done
fi
