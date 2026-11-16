# Minimal .zshrc
# Loads eager and lazy configs from XDG-compliant dotfiles structure

# Prevent infinite function nesting
export FUNCNEST=200

# XDG Base Directory Specification
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# eager/ runs now, before the first prompt.
for config_file in "$XDG_CONFIG_HOME/zsh/eager"/*.zsh(N); do
  source "$config_file"
done
unset config_file

# lazy/ runs once the first prompt is drawn, as one zsh-defer task
# (eager/15-defer.zsh), so nothing in it exists in `zsh -i -c`. -2 keeps
# stderr, so a broken lazy file says so; -m and -d skip re-running the
# precmd and chpwd hooks (mise, starship) after it. The files run inside a
# function: a top-level typeset or local in one stays local to it.
_zsh_source_lazy() {
  local f
  for f in "$XDG_CONFIG_HOME/zsh/lazy"/*.zsh(N); do
    source "$f"
  done
}
if (( $+functions[zsh-defer] )); then
  zsh-defer -2 -m -d _zsh_source_lazy
else
  _zsh_source_lazy
fi
