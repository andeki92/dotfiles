#!/usr/bin/env zsh

# Kubernetes tools completion - loaded lazily after the main completion system

_setup_k8s_completion() {
  # Only setup completions if commands exist
  if (( $+commands[kubectl] )); then
    source <(kubectl completion zsh)
  fi

  # Completion for kubectx and kubens if installed
  if (( $+commands[kubectx] )); then
    [[ -f ~/.config/kubectx/completion/kubectx.zsh ]] && source ~/.config/kubectx/completion/kubectx.zsh
  fi

  if (( $+commands[kubens] )); then
    [[ -f ~/.config/kubectx/completion/kubens.zsh ]] && source ~/.config/kubectx/completion/kubens.zsh
  fi
}

# Defer the completion setup to run after the main completion system is initialized
zsh-defer _setup_k8s_completion 