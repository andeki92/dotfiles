#!/usr/bin/env bash
# Script to verify WSL detection methods

echo "=== WSL Detection Methods Check ==="
echo

# Check WSLInterop
echo "Method 1: /proc/sys/fs/binfmt_misc/WSLInterop"
if [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
  echo "✅ Found WSLInterop - This is WSL"
else
  echo "❌ No WSLInterop - Not WSL or disabled"
fi
echo

# Check uname -r
echo "Method 2: Kernel version check"
kernel_ver=$(uname -r)
echo "Kernel version: $kernel_ver"
if [[ "$kernel_ver" =~ [Mm]icrosoft ]]; then
  echo "✅ 'microsoft' found in kernel version - This is WSL"
else
  echo "❌ 'microsoft' not found in kernel version - Not WSL"
fi
echo

# Check WSL_DISTRO_NAME
echo "Method 3: WSL_DISTRO_NAME environment variable"
if [[ -n "${WSL_DISTRO_NAME}" ]]; then
  echo "✅ WSL_DISTRO_NAME is set to: $WSL_DISTRO_NAME - This is WSL"
else
  echo "❌ WSL_DISTRO_NAME is not set - Not WSL or variable unset"
fi
echo

# Source platform detection script
echo "Checking platform detection from zsh config..."
# Convert is_wsl to bash compatible syntax
is_wsl() {
  [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]] || 
  [[ "$(uname -r)" =~ [Mm]icrosoft ]] ||
  [[ -n "${WSL_DISTRO_NAME}" ]]
}

echo -n "is_wsl() detection result: "
if is_wsl; then
  echo "✅ This is WSL"
  
  # Try to set Git config
  echo "Setting Git os.name to wsl..."
  git config --global os.name wsl
  
  # Check if it worked
  echo "Git os.name is now: $(git config --get os.name)"
else
  echo "❌ Not running in WSL"
fi
echo

echo "=== Check complete ===" 