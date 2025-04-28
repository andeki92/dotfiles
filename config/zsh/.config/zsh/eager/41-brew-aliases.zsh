# Homebrew aliases and functions
# Provides shortcuts for common Homebrew operations

# Update Homebrew, upgrade all packages, and clean up
alias brewup="brew update && brew upgrade && brew cleanup"

# Show what would be installed/upgraded without actually doing it
alias brewdry="brew upgrade --dry-run"

# Dump current packages to Brewfile
alias brewdump="brew bundle dump --force"

# Install everything from Brewfile
alias brewinstall="brew bundle"

# Check which packages in Brewfile are installed or missing
alias brewcheck="brew bundle check"

# Clean up (remove) outdated downloads and versions
alias brewclean="brew cleanup"

# Show packages that aren't in Brewfile (dry run)
alias brewcleanup="brew bundle cleanup"

# Remove packages that aren't in Brewfile
alias brewcleanupforce="brew bundle cleanup --force"

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

# Sync Brewfile from home directory to dotfiles repository
brewsync() {
  if [[ -f "$HOME/.config/brewfile/Brewfile" ]]; then
    cp "$HOME/.config/brewfile/Brewfile" "$HOME/.dotfiles/config/brew/.config/brewfile/"
    echo "Brewfile synced to dotfiles repository"
  else
    echo "Brewfile not found at ~/.config/brewfile/Brewfile"
  fi
} 