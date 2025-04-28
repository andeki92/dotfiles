# Git Aliases

# Status
alias gs='git status'

# Add
alias ga='git add'
alias gaa='git add .'

# Commit
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'

# Push
alias gp=git_push_with_pr

# Pull/Fetch
alias gf='git fetch'
alias gfa='git fetch --all'
alias gpl='git pull'
alias gpr='git pull --rebase'

# Branch/Checkout
alias gb='git branch'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gcom='git checkout main'

# Stash
alias gst='git stash'
alias gsta='git stash apply'
alias gstp='git stash pop'
alias gsts='git stash show'

# Diff/Log
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph'
alias glog='git log --oneline --decorate --graph --all'

# Reset/Clean
alias grs='git reset'
alias grsh='git reset --hard'
alias gclean='git clean -fd'

# Tag
alias gt='git tag'
alias gts='git tag -l'

# Cherry-pick/Revert/Amend
alias gcp='git cherry-pick'
alias grv='git revert' 