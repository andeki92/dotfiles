#!/usr/bin/env bash
# One-shot post-stow setup: link the platform-specific git config.
# Run this after `stow -R .`.

set -euo pipefail

GIT_CONFIG_DIR="$HOME/.config/git"
PLATFORM_LINK="$GIT_CONFIG_DIR/config-platform"

if [[ ! -d "$GIT_CONFIG_DIR" ]]; then
  echo "$GIT_CONFIG_DIR does not exist — did you run \`stow -R .\` first?" >&2
  exit 1
fi

case "$(uname)" in
  Darwin)
    target="$GIT_CONFIG_DIR/config-macos"
    ;;
  Linux)
    if [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]] || \
       [[ "$(uname -r)" =~ [Mm]icrosoft ]] || \
       [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
      target="$GIT_CONFIG_DIR/config-wsl"
    else
      target="$GIT_CONFIG_DIR/config-linux"
    fi
    ;;
  *)
    echo "Unsupported platform: $(uname)" >&2
    exit 1
    ;;
esac

if [[ ! -f "$target" ]]; then
  echo "Expected platform config not found: $target" >&2
  exit 1
fi

ln -sf "$target" "$PLATFORM_LINK"
echo "Linked $PLATFORM_LINK -> $target"
