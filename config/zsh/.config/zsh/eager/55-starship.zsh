# Starship prompt. Eager, because it draws the first prompt; its init script
# comes from the cache (eager/16-cached-init.zsh). starship itself comes from
# mise (config/mise), so this runs after eager/50-mise.zsh.
if _cached_init starship starship init zsh --print-full-init; then
  source "$REPLY"
  # starship.toml has no right_format, so the right prompt is always empty;
  # without this, starship still runs once more per prompt to print nothing.
  # Remove this line if you add a right_format.
  RPROMPT=''
else
  PROMPT='%F{cyan}> %f'
  RPROMPT=''
  print -u2 "starship not found: using a plain prompt. It comes from mise (config/mise)."
fi
