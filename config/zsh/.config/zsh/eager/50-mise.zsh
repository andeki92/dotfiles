# mise-en-place: activate eagerly, so tools are on PATH before the prompt.
# Completion comes from Homebrew's site-functions/_mise, which compinit
# (lazy/60-completion.zsh) picks up; nothing to load here.
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
else
  print -u2 "mise not found: add it to the Brewfile (config/brew) and run brew bundle --global."
fi
