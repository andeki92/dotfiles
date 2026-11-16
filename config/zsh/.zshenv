# Read by every zsh: interactive or not, login or not, scripts and `zsh -c`
# included. Only plain exports that every zsh should have go here. No forks,
# no output.
#
# Not here:
# - PATH: on macOS, /etc/zprofile's path_helper reorders it after this file
#   runs, so it's set in eager/10-platform.zsh and eager/30-brew.zsh.
# - The GIT_CONFIG_* gitlab.com credential (eager/10-platform.zsh): the
#   claude launchers strip it from agent sessions, and this file would hand
#   it back to every shell an agent starts.

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Each is a default: a value the parent set wins, as when `c` starts claude
# with DO_NOT_TRACK=0 or a project's .env sets KUBECONFIG.

# DO_NOT_TRACK: the cross-tool convention (consoledonottrack.com) for "send no
# usage data". Tools that ignore it still need their own switch.
export DO_NOT_TRACK="${DO_NOT_TRACK:-1}"
export HOMEBREW_NO_ANALYTICS="${HOMEBREW_NO_ANALYTICS:-1}"
export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"   # skip brew's slow implicit update

# One KUBECONFIG list: ~/.kube/config first, then every file in
# ~/.kube/configs/ (such as homelab's task talos:kube-login). (N) lets the
# glob match nothing. Built once per terminal and inherited by the shells
# inside it, so a new file there needs a new terminal (rl isn't enough).
if [[ -z "${KUBECONFIG:-}" ]]; then
  export KUBECONFIG="$HOME/.kube/config"
  for f in "$HOME"/.kube/configs/*.yaml(N); do KUBECONFIG="$KUBECONFIG:$f"; done
  unset f
fi
