# FZF Configuration - ZSH
# These environment variables must be set early as they affect FZF's behavior at initialization

# Set default FZF configuration options
export FZF_DEFAULT_OPTS="--height 50% --layout=reverse --border=rounded --inline-info --preview-window=right:60%:wrap --pointer=→"

# Use fd (https://github.com/sharkdp/fd) for more efficient file finding
if command -v fd &> /dev/null; then
  # Search files (respecting .gitignore)
  export FZF_DEFAULT_COMMAND='fd --type file --color=always --follow --hidden --exclude .git --exclude node_modules 2>/dev/null'
  # For Ctrl+T, use relative paths and no color codes
  export FZF_CTRL_T_COMMAND="cd \$PWD && fd --type file --color=never --follow --hidden --exclude .git --exclude node_modules --strip-cwd-prefix 2>/dev/null"
  # Search directories
  export FZF_ALT_C_COMMAND='fd --type directory --color=never --follow --hidden --exclude .git --exclude node_modules --strip-cwd-prefix 2>/dev/null'
else
  # Fallback to find if fd not available - use basename for cleaner display
  export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/\.git/*" -not -path "*/node_modules/*" 2>/dev/null'
  export FZF_CTRL_T_COMMAND='find . -type f -not -path "*/\.git/*" -not -path "*/node_modules/*" -printf "%P\n" 2>/dev/null'
  export FZF_ALT_C_COMMAND='find . -type d -not -path "*/\.git/*" -not -path "*/node_modules/*" -printf "%P\n" 2>/dev/null'
fi

# Add preview capabilities with better error handling and formatting
export FZF_CTRL_T_OPTS="--ansi --prompt='File > ' --header='Select files (TAB=multi-select, ESC=exit)' --marker='✓' --preview='f=\"\$PWD/{}\"
if [[ -f \"\$f\" ]]; then
  if [[ \"\$f\" == *.md || \"\$f\" == *.txt ]]; then
    bat --style=numbers --color=always --line-range :300 \"\$f\" 2>/dev/null
  elif [[ \"\$f\" == *.jpg || \"\$f\" == *.jpeg || \"\$f\" == *.png ]]; then
    echo \"[Image file: \$f]\"
  else
    bat --style=numbers --color=always --line-range :300 \"\$f\" 2>/dev/null || cat \"\$f\" 2>/dev/null || echo \"Binary file: \$f\"
  fi
else
  echo \"Not found: \$f\"
fi'"

export FZF_ALT_C_OPTS="--ansi --prompt='CD > ' --header='Select directory to cd into (⌥C or ESC-c)' --preview='d=\"\$PWD/{}\"
if [[ -d \"\$d\" ]]; then
  ls -la --color=always \"\$d\" | head -30 2>/dev/null
else
  echo \"Not a directory: \$d\"
fi'"

export FZF_CTRL_R_OPTS="--ansi --prompt='History > ' --header='Command history (ESC=exit, Enter=execute)' --preview 'echo {}' --preview-window down:3:wrap --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)'"

# Add key bindings if in interactive mode
if [[ $- == *i* ]]; then
 
  # Ctrl+P - Quick project switching
  bindkey -s '^p' 'fp^M'
  
  # Ctrl+O - Directory navigation
  bindkey -s '^o' 'fcd^M'
fi