# Homebrew aliases and functions
# Provides shortcuts for common Homebrew operations

# brewup (update, upgrade, cleanup) is in lazy/70-updates.zsh, which also
# records the update for the reminder.

# Show what would be installed/upgraded without actually doing it
alias brewdry="brew upgrade --dry-run"

# Dump current packages to Brewfile (global location)
alias brewdump="brew bundle dump --global --force"

# Install everything from Brewfile (global location)
alias brewinstall="brewup && brew bundle --global"

# Check which packages in Brewfile are installed or missing
alias brewcheck="brew bundle check --global"

# Clean up (remove) outdated downloads and versions
alias brewclean="brew cleanup"

# Show packages that aren't in Brewfile (dry run)
alias brewcleanup="brew bundle cleanup --global"

# Remove packages that aren't in Brewfile
alias brewcleanupforce="brew bundle cleanup --global --force"

# List installed packages
alias brewls="brew list"

# Show package info
brewinfo() {
  brew info "$@"
}

# Uninstall a package and its dependencies
brewrm() {
  brew uninstall "$@" && brew autoremove
}

# Search for a package
brewfind() {
  brew search "$@"
}

# List all brew commands
alias brewhelp="brew commands"

# Edit the Brewfile directly
brewedit() {
  ${EDITOR:-vim} "${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/Brewfile"
}

# Display path to global Brewfile
alias brewfile="echo ${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/Brewfile"

# No brewsync: ~/.config/homebrew is stowed from this repo, so brewdump
# already writes the repo's Brewfile.
