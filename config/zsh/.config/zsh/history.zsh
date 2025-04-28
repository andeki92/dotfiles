# Minimal history configuration

# History file location
export HISTFILE="$XDG_DATA_HOME/zsh/history"

# Ensure history directory exists
if [[ ! -d "$XDG_DATA_HOME/zsh" ]]; then
  mkdir -p "$XDG_DATA_HOME/zsh"
fi

# History settings
export HISTSIZE=1000
export SAVEHIST=1000

# Don't save duplicates
setopt HIST_IGNORE_DUPS

# Append to history file
setopt APPEND_HISTORY

# Add timestamps to history
setopt EXTENDED_HISTORY 