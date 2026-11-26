# Atuin shell history integration (local mode — sync and Threads disabled in
# ~/.config/atuin/config.toml). Cached per atuin binary via eager/16-cached-init.zsh.
if (( $+commands[atuin] )); then
  if _cached_init atuin atuin init zsh --disable-up-arrow; then
    source "$REPLY"
  fi
fi
