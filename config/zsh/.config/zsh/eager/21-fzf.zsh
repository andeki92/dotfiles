# FZF Configuration - ZSH
# These environment variables must be set early as they affect FZF's behavior at initialization

# Set default FZF configuration options
export FZF_DEFAULT_OPTS="--ansi --height 50% --layout=reverse --border=rounded --inline-info --pointer=→"

# Use fd (https://github.com/sharkdp/fd) for more efficient file finding
if command -v fd &> /dev/null; then
  # Search files (respecting .gitignore)
  export FZF_DEFAULT_COMMAND='fd --type file --color=always --follow --hidden --exclude .git --exclude node_modules 2>/dev/null'
  # For Ctrl+T, use relative paths and no color codes
  export FZF_CTRL_T_COMMAND="fd --type file --color=never --follow --hidden --exclude .git --exclude node_modules --strip-cwd-prefix 2>/dev/null"
  # Search directories
  export FZF_ALT_C_COMMAND='fd --type directory --color=never --follow --hidden --exclude .git --exclude node_modules --strip-cwd-prefix 2>/dev/null'
else
  # Fallback to find if fd not available. sed strips the leading ./, as GNU
  # find's -printf "%P" would; BSD find on macOS has no -printf.
  export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/\.git/*" -not -path "*/node_modules/*" 2>/dev/null'
  export FZF_CTRL_T_COMMAND='find . -type f -not -path "*/\.git/*" -not -path "*/node_modules/*" 2>/dev/null | sed "s|^\./||"'
  export FZF_ALT_C_COMMAND='find . -mindepth 1 -type d -not -path "*/\.git/*" -not -path "*/node_modules/*" 2>/dev/null | sed "s|^\./||"'
fi

# Add preview capabilities with better error handling and formatting - uses explicit quoting for Ghostty
export FZF_CTRL_T_OPTS="--ansi --prompt='File > ' --header='Select files (Ctrl+T, TAB=multi-select)' --marker='✓' --preview='
f=\"\$PWD/{}\"
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

export FZF_ALT_C_OPTS="--ansi --prompt='CD > ' --header='Select directory (Ctrl+O)' --preview='
d=\"\$PWD/{}\"
if [[ -d \"\$d\" ]]; then
  ls -la --color=always \"\$d\" | head -30 2>/dev/null
else
  echo \"Not a directory: \$d\"
fi'"

export FZF_CTRL_R_OPTS="--ansi --prompt='History > ' --header='Command history (Ctrl+R, Enter=execute)' --preview='echo {}' --preview-window=down:3:wrap --bind='ctrl-y:execute-silent(echo -n {2..} | pbcopy)'"

# Keys that run a command (fp, fcd, fe are in lazy/51-fzf.zsh). Each is a
# widget, not `bindkey -s 'fp^M'`, which typed the name onto whatever was
# already on the line and ran the mix. push-line parks the line you were
# typing and puts it back at the next prompt.
if [[ $- == *i* ]]; then
  _bind_command() {  # _bind_command <key> <command>
    eval "_run_$2() { zle push-line; BUFFER=${(q)2}; zle accept-line }"
    zle -N _run_$2
    bindkey "$1" _run_$2
  }
  _bind_command '^p' fp    # Ctrl+P - project switcher
  _bind_command '^o' fcd   # Ctrl+O - cd into a directory
  _bind_command '^f' fe    # Ctrl+F - open files in $EDITOR
  # No Ctrl+H: some terminals send it for Backspace. fzf's Ctrl+R does what
  # fh did; fh is still there to type.
  unfunction _bind_command
fi

# Note: Standard FZF keybindings (Ctrl+T, Ctrl+R) are defined in the lazy-loaded file
# They are implemented with ZLE widgets for better Ghostty compatibility
