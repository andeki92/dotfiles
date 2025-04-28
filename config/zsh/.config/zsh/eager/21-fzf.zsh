# FZF Configuration - ZSH
# These environment variables must be set early as they affect FZF's behavior at initialization

# Set default FZF configuration options
export FZF_DEFAULT_OPTS="--height 50% --layout=reverse --border --inline-info --preview-window=right:60%:wrap"

# Use fd (https://github.com/sharkdp/fd) for more efficient file finding
if command -v fd &> /dev/null; then
  # Search files (respecting .gitignore)
  export FZF_DEFAULT_COMMAND='fd --type file --color=always --follow --hidden --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  # Search directories
  export FZF_ALT_C_COMMAND='fd --type directory --color=always --follow --hidden --exclude .git'
else
  # Fallback to find if fd not available
  export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/\.git/*" -not -path "*/node_modules/*"'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='find . -type d -not -path "*/\.git/*" -not -path "*/node_modules/*"'
fi

# Add preview capabilities
export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :500 {}' --bind 'ctrl-/:change-preview-window(down|hidden|)'"
export FZF_ALT_C_OPTS="--preview 'ls -la {}'"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window down:3:wrap --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)'"

# ----------------------------------------
# Productivity Functions
# ----------------------------------------

# Quick file open with editor
fe() {
  local files
  IFS=$'\n' files=($(fzf --query="$1" --multi --select-1 --exit-0 --preview 'bat --style=numbers --color=always --line-range :500 {}'))
  [[ -n "$files" ]] && ${EDITOR:-vim} "${files[@]}"
}

# cd to selected directory
fcd() {
  local dir
  dir=$(fd --type d --hidden --follow --exclude ".git" | fzf --preview 'ls -la {}')
  [[ -n "$dir" ]] && cd "$dir"
}

# Search file contents (requires ripgrep)
fif() {
  if [ ! "$(command -v rg)" ]; then
    echo "Error: ripgrep (rg) is required for this function"
    return 1
  fi
  
  local selected
  selected=$(
    rg --color=always --line-number --no-heading --smart-case "${*:-}" |
      fzf --ansi \
          --color "hl:-1:underline,hl+:-1:underline:reverse" \
          --preview "bat --style=numbers --color=always --highlight-line {2} {1}" \
          --preview-window "up,60%,border-bottom,+{2}+3/3,~3"
  )
  
  if [[ -n "$selected" ]]; then
    local file=$(echo "$selected" | awk -F: '{print $1}')
    local line=$(echo "$selected" | awk -F: '{print $2}')
    ${EDITOR:-vim} "$file" +$line
  fi
}

# Git commit browser with previews
fgc() {
  local commits=$(
    git log --graph --color=always --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" |
    fzf --ansi --no-sort --reverse --multi \
        --preview "echo {} | grep -o '[a-f0-9]\{7\}' | head -1 | xargs -I % git show --color=always %" \
        --bind "ctrl-m:execute:
                (grep -o '[a-f0-9]\{7\}' | head -1 |
                xargs -I % git show --color=always % | less -R) << 'FZF-EOF'
                {}
FZF-EOF"
  )
}

# Kill process
fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m --header="[kill process]" | awk '{print $2}')
  if [ "x$pid" != "x" ]; then
    echo $pid | xargs kill -${1:-9}
  fi
}

# Tmux session switcher
ftm() {
  local session
  session=$(tmux list-sessions -F "#{session_name}" | fzf --query="$1" --select-1 --exit-0) &&
  tmux switch-client -t "$session" 2>/dev/null || tmux attach-session -t "$session" || echo "No sessions found."
}

# Project switcher
fproj() {
  local dir
  dir=$(find ~/Projects -type d -maxdepth 2 -not -path "*/\.*" | fzf --preview 'ls -la {}')
  [[ -n "$dir" ]] && cd "$dir"
}

# Enhanced history search
fh() {
  print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac | sed -E 's/ *[0-9]*\*? *//' | sed -E 's/\\/\\\\/g')
}

# Browser bookmark search (for macOS Chrome)
fbm() {
  local bookmarks_path="$HOME/Library/Application Support/Google/Chrome/Default/Bookmarks"
  
  if [ ! -f "$bookmarks_path" ]; then
    echo "Chrome bookmarks file not found at: $bookmarks_path"
    return 1
  fi
  
  local jq_script='
    def ancestors: while(. | length >= 2; del(.[-1,-2]) | . + [.[-2].children[] | select(.id == .[-1].parent_id)]) | .;
    def path: reverse | map(.name) | join("/");
    . as $in | paths(.url?) as $p | $in | getpath($p) | {name,url, path: [$p[0:-1] | ancestors | path] | first}
  '
  
  jq -r "$jq_script" < "$bookmarks_path" |
    jq -r '[.path, .name, .url] | @tsv' |
    column -t -s $'\t' |
    fzf --nth 1,2 --with-nth 1,2 --preview "echo {3}" |
    awk '{print $NF}' |
    xargs open
}

# Man page browser with preview
fman() {
  man -k . | 
  fzf -q "$1" --prompt='Man> ' \
      --preview "echo {1} | sed 's/(.*//' | xargs -I{} man -Pcat {} 2>/dev/null" \
      --preview-window=right:70% |
  awk '{print $1}' |
  sed 's/(.*//' |
  xargs -I{} man {}
}

# Add key bindings if in interactive mode
if [[ $- == *i* ]]; then
  # Ctrl+G - Git status files
  bindkey -s '^G' 'git status --short | fzf --preview "git diff --color=always {2}" | awk '\''{print $2}'\''^M'
  
  # Alt+P - Quick project switching
  bindkey -s '^[p' 'fproj^M'
  
  # Alt+F - Find in files
  bindkey -s '^[f' 'fif^M'
fi 