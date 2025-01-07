alias fd="fdfind"

# --- eza 📃 (https://github.com/eza-community/eza) ---
alias ls='eza --color=always --group-directories-first --icons'
alias ll='eza -la --icons --octal-permissions --group-directories-first'
alias l='eza --tree --level=2 --color=always --group-directories-first --icons'
alias la='eza --long --all --group --group-directories-first'
alias lx='eza -lbhHigUmuSa@ --time-style=long-iso --git --color-scale --color=always --group-directories-first --icons'
alias l.="eza -a | grep -E '^\.'" # show dot-prefixed files

# -- kubectl 🚢 (https://kubernetes.io/docs/reference/kubectl/)
# kubernetes aliases
alias k="kubectl"

alias kg="k get"
alias kgp="kg pods"
alias kgd="kg deployments"
alias kgs="kg svc"
alias kgi="kg ingress"

alias kd="k describe"
alias kdp="kd pods"
alias kdd="kd deployments"
alias kds="kd service"
alias kdi="kd ingress"

alias kpf="k port-forward"
alias kl="k logs"

# kubernetes plugin shortcuts
alias kx="k ctx"
alias kn="k ns"

# kubectl function aliases
alias kex="kubectl_exec_into_pod"
alias kps="kubectl_psql_start"

alias rgf='rg --files | rg'

alias gd="cd ~/.dotfiles"
alias gw="cd ~/workspace"
alias gp="cd ~/privatespace"

alias rl="source ~/.zshrc && clear"

alias go-reshim='asdf reshim golang && export GOROOT="$(asdf where golang)/go/"'

# on ubuntu/debian bat is installed as batcat
type batcat >/dev/null 2>&1 && alias bat="batcat"
alias cat="bat"

# git aliases
alias g="git pull"
alias gp="git push"
alias ga="git add ."

alias gc="git commit -m"
alias gca="git commit --amend"

alias gsm="git switch main"
alias gcb="git checkout -b"
