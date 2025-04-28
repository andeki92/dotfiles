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

# Platform-specific settings (minimal)
if is_macos; then
  # macOS-specific minimal settings
  export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
elif is_linux; then
  # Linux-specific minimal settings
  export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:$PATH"
  
  if is_wsl; then
    # WSL-specific minimal settings
    # Add Windows interop settings here if needed
  fi
fi 