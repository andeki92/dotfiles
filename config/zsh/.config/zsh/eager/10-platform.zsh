# Platform detection
# These functions allow for platform-specific configurations

is_macos() {
  [[ "$(uname)" == "Darwin" ]]
}

is_linux() {
  [[ "$(uname)" == "Linux" ]]
}

is_wsl() {
  # Most reliable WSL detection method:
  # Check for /proc/sys/fs/binfmt_misc/WSLInterop
  [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]] || 
  # Fallback: check kernel version string for "microsoft" or "Microsoft"
  [[ "$(uname -r)" =~ [Mm]icrosoft ]] ||
  # Fallback: check if WSL_DISTRO_NAME environment variable exists
  [[ -n "${WSL_DISTRO_NAME}" ]]
}

# Ensure PATH elements are unique to prevent duplication during reload
typeset -U path

# Platform-specific settings (minimal)
if is_macos; then
  # macOS-specific minimal settings
  path=(/usr/local/bin /usr/bin /bin /usr/sbin /sbin $path)
  
  # Set Git os configuration for macOS
  git config --global os.name macos
elif is_linux; then
  # Linux-specific minimal settings
  path=(/usr/local/bin /usr/bin /bin /usr/local/sbin /usr/sbin /sbin $path)
  
  if is_wsl; then
    # WSL-specific minimal settings
    # Add Windows interop settings here if needed
    
    # Set Git os configuration for WSL
    git config --global os.name wsl
  else
    # Set Git os configuration for standard Linux
    git config --global os.name linux
  fi
fi 