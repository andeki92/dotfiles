# Homebrew aliases and functions
# Provides shortcuts for common Homebrew operations

# Update Homebrew, upgrade all packages, and clean up
alias brewup="brew update && brew upgrade && brew cleanup"

# Show what would be installed/upgraded without actually doing it
alias brewdry="brew upgrade --dry-run"

# Dump current packages to Brewfile (global location)
alias brewdump="brew bundle dump --global --force"

# Install everything from Brewfile (global location)
alias brewinstall="brew bundle --global"

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

# Sync Brewfile from system to dotfiles repository
brewsync() {
  local src="${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/Brewfile"
  local dest="$HOME/.dotfiles/config/brew/.config/homebrew/Brewfile"
  
  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
    echo "Brewfile synced from $src to $dest"
  else
    echo "Error: Brewfile not found at $src"
    return 1
  fi
} 