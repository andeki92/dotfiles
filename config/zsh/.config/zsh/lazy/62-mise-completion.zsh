#!/usr/bin/env zsh

# Mise-en-place completion - loaded lazily after the main completion system

_setup_mise_completion() {
  # Only setup completions if commands exist
  if (( $+commands[mise] )); then
    source <(mise completion zsh)
  fi
}

# Defer the completion setup to run after the main completion system is initialized
zsh-defer _setup_mise_completion