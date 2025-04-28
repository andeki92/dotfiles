# FZF Lazy-loaded functionality
# These items don't need to be loaded immediately during shell startup

# Extended file finder with custom options
ffx() {
  local result
  result=$(fd --type file --color=always "$@" | 
           fzf --ansi --multi --preview 'bat --style=numbers --color=always --line-range :500 {}')
  echo "$result"
}

# Advanced git branch management
fbr() {
  local branches branch
  branches=$(git branch --all | grep -v HEAD) &&
  branch=$(echo "$branches" |
           fzf --ansi --preview="git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --color=always \$(echo {} | sed 's/^[* ]*//' | sed 's#remotes/[^/]*/##')" |
           sed 's/^[* ]*//' | sed 's#remotes/[^/]*/##') &&
  git checkout "$branch"
}

# Docker container management
fdoc() {
  local container
  container=$(docker ps --format "{{.ID}} - {{.Names}} - {{.Image}} ({{.Status}})" | 
              fzf --preview 'docker logs --tail 50 $(echo {} | cut -d "-" -f 1 | xargs)') && 
  container_id=$(echo $container | cut -d "-" -f 1 | xargs)
  
  if [[ -n $container_id ]]; then
    echo "Container ID: $container_id"
    echo "1) Show logs"
    echo "2) Bash into container"
    echo "3) Stop container"
    read -k 1 "action?Action: "
    echo ""
    
    case $action in
      1)
        docker logs -f $container_id
        ;;
      2)
        docker exec -it $container_id bash || docker exec -it $container_id sh
        ;;
      3)
        docker stop $container_id
        ;;
    esac
  fi
}

# NPM scripts runner
fnpm() {
  local script
  script=$(cat package.json | jq -r '.scripts | keys[] | . + " --> " + ..' | 
           fzf --preview "cat package.json | jq -r '.scripts.\"$(echo {} | cut -d ' ' -f1)\"'") &&
  npm run $(echo $script | cut -d ' ' -f1)
}

# Enhanced search and replace in files (requires ripgrep, sed)
fsr() {
  if [ ! "$(command -v rg)" ]; then
    echo "Error: ripgrep (rg) is required for this function"
    return 1
  fi
  
  local search_term
  echo -n "Search term: "
  read search_term
  
  if [[ -z "$search_term" ]]; then
    echo "Search term cannot be empty"
    return 1
  fi
  
  local replace_term
  echo -n "Replace with: "
  read replace_term
  
  local selected_files
  selected_files=$(rg --files-with-matches --no-messages "$search_term" | 
                   fzf --multi --preview "rg --color=always -p -C 3 '$search_term' {}")
  
  if [[ -n "$selected_files" ]]; then
    echo "$selected_files" | xargs sed -i '' "s/$search_term/$replace_term/g"
    echo "Replaced '$search_term' with '$replace_term' in selected files."
  fi
}

# Cheatsheet viewer for common commands
fcheat() {
  local cheats="
  # File Operations
  ls -la                   # List all files with details
  find . -name '*.js'      # Find files by extension
  chmod +x file            # Make file executable
  
  # Process Management
  ps aux | grep process    # Find process
  kill -9 PID              # Force kill process
  
  # Git Commands
  git add .                # Stage all changes
  git commit -m 'msg'      # Commit with message
  git push origin master   # Push to master
  git branch -d branch     # Delete local branch
  
  # Network
  curl -I example.com      # HTTP headers
  ssh user@host            # SSH connection
  ping -c 5 example.com    # Ping 5 times
  
  # Archives
  tar -xzvf file.tar.gz    # Extract .tar.gz
  tar -czvf file.tar.gz dir # Create .tar.gz
  
  # System
  df -h                    # Disk usage
  free -h                  # Memory usage
  htop                     # Process viewer
  
  # Text Processing
  grep 'pattern' file      # Search in file
  sed 's/old/new/g' file   # Replace in file
  awk '{print $1}' file    # Print first column
  "
  
  echo "$cheats" | fzf --ansi
}

# Load FZF completion
if [[ -f ~/.fzf.zsh ]]; then
  source ~/.fzf.zsh
elif [[ -f /usr/local/opt/fzf/shell/completion.zsh ]]; then
  source /usr/local/opt/fzf/shell/completion.zsh
elif [[ -f /opt/homebrew/opt/fzf/shell/completion.zsh ]]; then
  source /opt/homebrew/opt/fzf/shell/completion.zsh
fi 