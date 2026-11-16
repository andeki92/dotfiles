#!/usr/bin/env zsh

# One KUBECONFIG list: ~/.kube/config first, then every file in
# ~/.kube/configs/ (such as homelab's task talos:kube-login). (N) lets the
# glob match nothing. A shell started before a new file appears needs a restart.
export KUBECONFIG="$HOME/.kube/config"
for f in "$HOME"/.kube/configs/*.yaml(N); do KUBECONFIG="$KUBECONFIG:$f"; done
unset f

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

# _kpod <pattern> — print the first pod whose name matches <pattern> (a regex)
_kpod() {
  kubectl get pods --no-headers 2>/dev/null | awk -v p="$1" '$1 ~ p { print $1; exit }'
}

# Helper function to follow logs of the first pod matching a pattern
klp() {
  [[ -n "$1" ]] || { echo "Usage: klp <pod-name-pattern>"; return 1; }
  local pod
  pod=$(_kpod "$1")
  [[ -n "$pod" ]] || { echo "No pod matching pattern: $1"; return 1; }
  echo "Following logs for pod: $pod"
  kubectl logs -f "$pod"
}

# Helper function to exec into the first pod matching a pattern:
# kep <pattern> [command [args...]], sh by default
kep() {
  [[ -n "$1" ]] || { echo "Usage: kep <pod-name-pattern> [command [args...]]"; return 1; }
  local pod
  pod=$(_kpod "$1")
  [[ -n "$pod" ]] || { echo "No pod matching pattern: $1"; return 1; }
  local -a cmd=("${@:2}")
  (( $#cmd )) || cmd=(sh)
  echo "Executing ${cmd[*]} in pod: $pod"
  kubectl exec -it "$pod" -- "${cmd[@]}"
}
