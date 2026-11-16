# _cached_init <name> <command...> — set REPLY to a file holding the output
# of <command...>, generated once and again only when the command's binary
# resolves to another file, as it does after an upgrade (brew and mise both
# put each version under a path of its own). Spares a fork per startup for
# init scripts that depend only on the binary, such as starship's and fzf's.
# Not for `mise activate`, whose output depends on the shell's current env.
#
# Source $REPLY where the script should run, not in here: inside a function,
# the script's typeset and local would stay local to it.
_cached_init() {
  local name=$1 bin=${commands[$2]:A} stamp
  [[ -n $bin ]] || return 1
  REPLY="$XDG_CACHE_HOME/zsh/init/$name.zsh"
  [[ -r $REPLY ]] && read -r stamp < "$REPLY"
  [[ $stamp == "# $bin" ]] && return 0
  [[ -d ${REPLY:h} ]] || mkdir -p "${REPLY:h}"
  if { print -r -- "# $bin"; command "${@:2}"; } > "$REPLY.$$" 2>/dev/null; then
    mv -f "$REPLY.$$" "$REPLY"
  else
    rm -f "$REPLY.$$"
    return 1
  fi
}
