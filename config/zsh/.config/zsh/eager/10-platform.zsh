# Platform detection
# These functions allow for platform-specific configurations

is_macos() {
  [[ "$(uname)" == "Darwin" ]]
}

is_linux() {
  [[ "$(uname)" == "Linux" ]]
}

is_wsl() {
  [[ -f /proc/version ]] && grep -q Microsoft /proc/version
}

# Ensure PATH elements are unique to prevent duplication during reload
typeset -U path

# Platform-specific settings (minimal)
if is_macos; then
  # macOS-specific minimal settings
  path=(/usr/local/bin /usr/bin /bin /usr/sbin /sbin $path)
elif is_linux; then
  # Linux-specific minimal settings
  path=(/usr/local/bin /usr/bin /bin /usr/local/sbin /usr/sbin /sbin $path)
  
  if is_wsl; then
    # WSL-specific minimal settings
    # Add Windows interop settings here if needed
  fi
fi 