# Update management for package managers and tools
# Provides notifications and commands for keeping tools updated

# Directory to store timestamps of last updates
UPDATE_TIMESTAMPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/updates"
mkdir -p "$UPDATE_TIMESTAMPS_DIR"

# Config - how often to remind for updates (in days)
: ${UPDATE_REMINDER_DAYS:=3}  # Default to 3 day if not set elsewhere

# ==== Update Functions ====

# Update Homebrew and all packages
update_brew() {
  echo "Updating Homebrew and packages..."
  brew update && brew upgrade && brew cleanup
  touch "$UPDATE_TIMESTAMPS_DIR/brew-update"
  echo "Homebrew update completed on $(date)"
}

# Update mise tools
update_mise() {
  echo "Updating mise and managed tools..."
  mise upgrade
  touch "$UPDATE_TIMESTAMPS_DIR/mise-update"
  echo "mise update completed on $(date)"
}

# Update everything
update_all() {
  update_brew
  update_mise
  echo "All updates completed!"
}

# ==== Check Functions ====

# Check if an update is needed based on timestamp file
_needs_update() {
  local timestamp_file="$UPDATE_TIMESTAMPS_DIR/$1-update"
  
  # If timestamp doesn't exist, definitely needs update
  if [[ ! -f "$timestamp_file" ]]; then
    return 0  # true in shell logic
  fi
  
  # Check if it's been more than UPDATE_REMINDER_DAYS since last update
  local last_update=$(stat -f "%m" "$timestamp_file")
  local now=$(date +%s)
  local days_since=$(( (now - last_update) / 86400 ))
  
  [[ $days_since -ge $UPDATE_REMINDER_DAYS ]]
}

# ==== Reminder System ====

# Check for updates needed and notify if so
check_updates() {
  local updates_needed=()
  
  if _needs_update "brew"; then
    updates_needed+=("Homebrew")
  fi
  
  if _needs_update "mise"; then
    updates_needed+=("mise")
  fi
  
  if (( ${#updates_needed[@]} > 0 )); then
    echo "📦 Updates available for: ${updates_needed[*]}"
    echo "Run 'update_all' to update everything, or:"
    [[ " ${updates_needed[*]} " =~ " Homebrew " ]] && echo "- 'update_brew' for Homebrew"
    [[ " ${updates_needed[*]} " =~ " mise " ]] && echo "- 'update_mise' for mise"
  fi
}

# ==== Aliases ====

# Set up aliases for update commands
alias brewup="update_brew"
alias miseup="update_mise"
alias updateall="update_all"

# ==== Auto-check on startup ====

# Run the check deferred so it doesn't slow down startup
zsh-defer check_updates 