#!/usr/bin/env zsh

# Kubernetes tools completion - loaded lazily after the main completion system

_setup_k8s_completion() {
  # Only setup completions if commands exist
  # Cached per kubectl binary (eager/16-cached-init.zsh): generating it costs
  # a 25ms kubectl run.
  if _cached_init kubectl kubectl completion zsh; then
    source "$REPLY"
  fi

  # kubectx and kubens: vendored in completions/, found by compinit
}

# Defer the completion setup to run after the main completion system is initialized
zsh-defer _setup_k8s_completion 