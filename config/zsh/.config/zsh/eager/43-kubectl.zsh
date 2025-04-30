#!/usr/bin/env zsh

# kubectl aliases
alias k='kubectl'
alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgd='kubectl get deployments'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kgpw='kubectl get pods -o wide'
alias kgdw='kubectl get deployments -o wide'
alias kgsw='kubectl get services -o wide'

alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias kdd='kubectl describe deployment'
alias kds='kubectl describe service'

alias kl='kubectl logs'
alias klf='kubectl logs -f'

alias kaf='kubectl apply -f'
alias kdel='kubectl delete'
alias kdf='kubectl delete -f'

alias kex='kubectl exec -it'
alias kc='kubectl config'
alias kcv='kubectl config view'
alias kcgc='kubectl config get-contexts'
alias kcuc='kubectl config use-context'
alias kccc='kubectl config current-context'

# kubectx alias
alias kx='kubectx'

# kubens alias
alias kn='kubens'

# Helper function to switch namespace and inform user
kns() {
  if [[ -z "$1" ]]; then
    kubens
  else
    echo "Switching to namespace: $1"
    kubens "$1"
  fi
}

# Helper function to display pod status with wide output
kstatus() {
  kubectl get pods -o wide
}

# Helper function to follow logs of the most recent pod matching a pattern
klp() {
  if [[ -z "$1" ]]; then
    echo "Usage: klp <pod-name-pattern>"
    return 1
  fi
  POD=$(kubectl get pods | grep "$1" | head -n 1 | awk '{print $1}')
  if [[ -z "$POD" ]]; then
    echo "No pod matching pattern: $1"
    return 1
  fi
  echo "Following logs for pod: $POD"
  kubectl logs -f "$POD"
}

# Helper function to exec into the most recent pod matching a pattern
kep() {
  if [[ -z "$1" ]]; then
    echo "Usage: kep <pod-name-pattern> [command]"
    return 1
  fi
  POD=$(kubectl get pods | grep "$1" | head -n 1 | awk '{print $1}')
  if [[ -z "$POD" ]]; then
    echo "No pod matching pattern: $1"
    return 1
  fi
  CMD=${2:-"sh"}
  echo "Executing $CMD in pod: $POD"
  kubectl exec -it "$POD" -- $CMD
}

# Completion for kubectl
if (( $+commands[kubectl] )); then
  source <(kubectl completion zsh)
fi

# Completion for kubectx and kubens if installed
if (( $+commands[kubectx] )); then
  # Load completion if available
  command -v compdef >/dev/null && {
    [[ -f ~/.config/kubectx/completion/kubectx.zsh ]] && source ~/.config/kubectx/completion/kubectx.zsh
  }
fi

if (( $+commands[kubens] )); then
  # Load completion if available
  command -v compdef >/dev/null && {
    [[ -f ~/.config/kubectx/completion/kubens.zsh ]] && source ~/.config/kubectx/completion/kubens.zsh
  }
fi 
