# Platform detection
# These functions allow for platform-specific configurations

# $OSTYPE and $(<file) need no fork, unlike $(uname).

is_macos() {
  [[ $OSTYPE == darwin* ]]
}

is_linux() {
  [[ $OSTYPE == linux* ]]
}

is_wsl() {
  # WSL's interop entry, then its env var, then "microsoft" in the kernel version
  [[ -e /proc/sys/fs/binfmt_misc/WSLInterop || -n "${WSL_DISTRO_NAME:-}" ]] ||
  [[ -r /proc/version && "$(</proc/version)" == *[Mm]icrosoft* ]]
}

# Ensure PATH elements are unique to prevent duplication during reload
typeset -U path

# Platform-specific settings (minimal).
# Note: ~/.config/git/config-platform is set up once by scripts/post-stow.sh,
# not on every shell startup.
if is_macos; then
  # macOS-specific minimal settings
  path=(/usr/local/bin /usr/bin /bin /usr/sbin /sbin $HOME/.local/bin $path)
  # Your own git reaches gitlab.com through glab. This lives in the shell, not
  # git/config-macos, so the claude launchers (eager/47-ai.zsh) can
  # strip it and agent sessions find no gitlab.com credential.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=credential.https://gitlab.com.helper
  export GIT_CONFIG_VALUE_0='!glab auth git-credential'
elif is_linux; then
  # Linux-specific minimal settings
  path=(/usr/local/bin /usr/bin /bin /usr/local/sbin /usr/sbin /sbin $HOME/.local/bin $path)

  if is_wsl; then
    # WSL-specific minimal settings
    # Add Windows interop settings here if needed
    path=(/home/linuxbrew/.linuxbrew $path)

    # opencode (only if installed under $HOME)
    if [[ -d "$HOME/.opencode/bin" ]]; then
        path=("$HOME/.opencode/bin" $path)
    fi

    # Load shrc directory shell files
    for file in $HOME/.shrc.d/*; do
      if [[ -r "$file" ]] && [[ "$file" =~ \.(sh|zsh)$ ]]; then
        source "$file"
      fi
    done

    export GIT_EXEC_PATH="$(git --exec-path)"
    export WSLENV=$WSLENV:GIT_EXEC_PATH/wp
  fi
fi

export PATH
