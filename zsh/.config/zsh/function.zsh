#!/usr/bin/env zsh

RED='\033[0;32m'
NC='\033[0m' # No Color

# Utility functions
functions command_exists() {
  command -v "$@" >/dev/null 2>&1
}

functions reload() {
    if [ -f  $HOME/.zshenv ]; then
        source $HOME/.zshrc
        clear
    fi
}

function kubectl_exec_sh() {
    local containers
    local container
    kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}' | fzf | read -r namespace pod
    containers=$(kubectl get pod -n $namespace $pod -o jsonpath='{.spec.containers[*].name}')
    container=$(echo ${containers/ /\\n} | fzf)
    kubectl exec -n $namespace --stdin --tty $pod --container $containers -- /bin/sh
}

function kubectl_exec_bash() {
    local containers
    local container
    kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}' | fzf | read -r namespace pod
    containers=$(kubectl get pod -n $namespace $pod -o jsonpath='{.spec.containers[*].name}')
    container=$(echo ${containers/ /\\n} | fzf)
    kubectl exec -n $namespace --stdin --tty $pod --container $container -- /bin/bash
}

function idea() {
    read -r pid < <(~/.local/share/JetBrains/Toolbox/apps/intellij-idea-ultimate/bin/idea $@ 2>&1 &)
}

function tb() {
     read -r pid < <(jetbrains-toolbox $@ 2>&1 &)
}

function github_clone_org() {
    if [ -z "$1" ]; then
        echo "Error: Organization name is required."
        return 1
    fi

    gh repo list $1 --limit 4000 | while read -r repo _; do
        gh repo clone "$repo"
    done
}

function clip() {
    if [ -z "$1" ]; then
        echo "Error: A file is required."
        return 1
    fi

    less -FX $1 | clip.exe
}

function is_linux() {
    if [ "$(uname -s)" = "Linux" ]; then
        return 0
    else
        return 1
    fi
}
