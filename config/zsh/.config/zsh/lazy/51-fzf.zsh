# FZF Lazy-loaded functionality
# These items don't need to be loaded immediately during shell startup

# Quick file open with editor
fe() {
  local files
  # Use cleaner formatting with shortened paths for better readability
  IFS=$'\n' files=($(fd --type file --hidden --follow --exclude ".git" 2>/dev/null | 
    fzf --query="$1" --multi --select-1 --exit-0 \
        --preview '[[ -f {} ]] && bat --style=numbers --color=always --line-range :300 {} || echo "Not a file"' \
        --preview-window="right:60%" \
        --height=70% \
        --layout=reverse \
        --border=rounded \
        --prompt="Edit > " \
        --pointer="→" \
        --marker="✓" \
        --header="Select file to edit (ESC=exit, Enter=open)" \
        --bind="ctrl-/:toggle-preview"))
  
  [[ -n "$files" ]] && ${EDITOR:-vim} "${files[@]}"
}

# cd to selected directory
fcd() {
  local dir
  dir=$(fd --type directory --hidden --follow --exclude ".git" 2>/dev/null | 
       fzf --preview '[[ -d {} ]] && ls -la --color=always {} | head -30 || echo "Not a directory"' \
           --height=70% \
           --layout=reverse \
           --border=rounded \
           --prompt="CD > " \
           --pointer="→" \
           --header="Select directory to cd into (ESC=exit, Enter=select)")
  
  [[ -n "$dir" ]] && cd "$dir"
}

# Search file contents (requires ripgrep)
fif() {
  if [ ! "$(command -v rg)" ]; then
    echo "Error: ripgrep (rg) is required for this function"
    return 1
  fi
  
  # Require a search term
  if [[ -z "$*" ]]; then
    echo "Usage: fif <search_term>"
    return 1
  fi
  
  local selected
  selected=$(
    # Add safeguards to prevent crashes
    rg --color=always --line-number --no-heading --smart-case "$*" 2>/dev/null |
      fzf --ansi \
          --color "hl:-1:underline,hl+:-1:underline:reverse" \
          --preview 'file=$(echo {} | cut -d: -f1); 
                    line=$(echo {} | cut -d: -f2);
                    if [[ -f "$file" ]]; then
                      bat --style=numbers --color=always --highlight-line $line "$file" 2>/dev/null || 
                      cat "$file" 2>/dev/null || 
                      echo "Cannot display file"
                    else
                      echo "File not found: $file"
                    fi' \
          --preview-window "up,60%,border-bottom,~3" \
          --height=70% \
          --layout=reverse \
          --border=rounded \
          --prompt="Find > " \
          --pointer="→" \
          --header="Search results for \"$*\" (ESC=exit, Enter=open file at line)" \
          --bind='ctrl-/:toggle-preview'
  )
  
  # Only try to open a file if something was selected
  if [[ -n "$selected" ]]; then
    # Extract file and line with more error checking
    local file line
    file=$(echo "$selected" | cut -d: -f1)
    line=$(echo "$selected" | cut -d: -f2)
    
    # Verify file exists before trying to open it
    if [[ -f "$file" && -n "$line" ]]; then
      ${EDITOR:-vim} "$file" +$line
    else
      echo "Cannot open file: $file at line $line"
      return 1
    fi
  fi
}

# Kill process
fkill() {
  local pid
  pid=$(ps -ef | sed 1d | 
        fzf -m --header="[kill process]" \
            --prompt="Kill > " \
            --pointer="→" \
            --height=50% \
            --layout=reverse \
            --border=rounded \
            --header="Select process to kill (TAB=multi-select)" | 
        awk '{print $2}')
  
  if [ "x$pid" != "x" ]; then
    echo $pid | xargs kill -${1:-9}
  fi
}

# Project switcher
fp() {
  local dir
  # Use basename in the display but keep full path for cd
  dir=$(find ~/privatespace -maxdepth 1 -type d -not -path "*/\.*" -not -path "*/node_modules/*" 2>/dev/null | 
       fzf --preview 'ls -la --color=always "{}" | head -20' \
           --height=70% \
           --layout=reverse \
           --border=rounded \
           --prompt="Project > " \
           --pointer="→" \
           --header="Select project directory (ESC=exit, Enter=select)" \
           --preview-window="right:60%" \
           --bind="ctrl-/:toggle-preview" \
           --delimiter="/" \
           --with-nth="-1" \
           --tiebreak=end)
  
  [[ -n "$dir" ]] && cd "$dir"
}

# Enhanced history search
fh() {
  print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | 
              fzf +s --tac \
                  --height=50% \
                  --layout=reverse \
                  --border=rounded \
                  --prompt="History > " \
                  --pointer="→" \
                  --header="Select command from history" | 
              sed -E 's/ *[0-9]*\*? *//' | 
              sed -E 's/\\/\\\\/g')
}

# Extended file finder with custom options
ffx() {
  local result
  result=$(fd --type file --hidden --follow --exclude ".git" --exclude "node_modules" 2>/dev/null | 
          fzf --ansi \
              --multi \
              --preview '[[ -f {} ]] && bat --style=numbers --color=always --line-range :300 {} || echo "Not a file"' \
              --height=70% \
              --layout=reverse \
              --border=rounded \
              --prompt="Find > " \
              --pointer="→" \
              --marker="✓" \
              --header="Select files (TAB=multi-select)")
  
  echo "$result"
}

# Advanced git branch management
fbr() {
  local branches branch
  branches=$(git branch --all | grep -v HEAD) &&
  branch=$(echo "$branches" |
           fzf --ansi \
               --preview="git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --color=always \$(echo {} | sed 's/^[* ]*//' | sed 's#remotes/[^/]*/##')" \
               --height=70% \
               --layout=reverse \
               --border=rounded \
               --prompt="Branch > " \
               --pointer="→" \
               --header="Select git branch to checkout" |
           sed 's/^[* ]*//' | 
           sed 's#remotes/[^/]*/##') &&
  git checkout "$branch"
}

# =======================================================
# Load FZF shell integration (completions and key bindings)
# =======================================================

# Source FZF key bindings script (enables Ctrl+R for history search)
if [[ -f ~/.fzf.zsh ]]; then
  source ~/.fzf.zsh
elif [[ -f /usr/local/opt/fzf/shell/key-bindings.zsh ]]; then
  source /usr/local/opt/fzf/shell/key-bindings.zsh
elif [[ -f /opt/homebrew/opt/fzf/shell/key-bindings.zsh ]]; then
  source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
fi

# Source FZF completions separately if not already loaded by key-bindings
if [[ -f /usr/local/opt/fzf/shell/completion.zsh ]]; then
  source /usr/local/opt/fzf/shell/completion.zsh
elif [[ -f /opt/homebrew/opt/fzf/shell/completion.zsh ]]; then
  source /opt/homebrew/opt/fzf/shell/completion.zsh
fi

# Explicitly ensure Ctrl+R works properly by setting up the binding
# This is a fallback in case the key-bindings.zsh file doesn't set it up
if [[ "$+functions[fzf-history-widget]" == "1" ]]; then
  bindkey '^R' fzf-history-widget
fi 