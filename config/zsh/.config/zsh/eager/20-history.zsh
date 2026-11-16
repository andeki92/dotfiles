# History: one file under XDG, shared live between shells, large enough to
# keep months of commands, with duplicates trimmed first and secrets kept
# out of the file.

HISTFILE="$XDG_DATA_HOME/zsh/history"
[[ -d ${HISTFILE:h} ]] || mkdir -p "${HISTFILE:h}"

# SAVEHIST is what the file keeps; HISTSIZE (in memory) is larger, so
# HIST_EXPIRE_DUPS_FIRST has duplicates to drop before any unique command.
HISTSIZE=120000
SAVEHIST=100000

setopt EXTENDED_HISTORY        # start time and duration for each entry
setopt SHARE_HISTORY           # write each command at once, read other shells'
                               # (it covers INC_APPEND_HISTORY; don't set both)
setopt HIST_FCNTL_LOCK         # lock the file with fcntl: no .LOCK files, safer with many shells
setopt HIST_EXPIRE_DUPS_FIRST  # trim duplicates first when the file is full
setopt HIST_IGNORE_DUPS        # skip a command identical to the one before it
setopt HIST_FIND_NO_DUPS       # up-arrow and search step over repeats
setopt HIST_IGNORE_SPACE       # a leading space keeps a command out of history
setopt HIST_REDUCE_BLANKS      # collapse extra whitespace before saving
setopt HIST_VERIFY             # show what !! and friends expand to before running

# Keep commands that look like they carry a secret out of the file: a literal
# value given to something named like a credential (GITHUB_TOKEN=abc,
# --password=x, ?session=...) or an auth header. A reference is saved as
# usual: TOKEN="$(security ...)", TOKEN=$OTHER, an empty TOKEN=, or a mention
# such as kubectl get secret or grep token. Returning 2 keeps the line in this shell's own history, so
# up-arrow still finds it, but never writes it, so it doesn't spread to other
# shells or outlive the session.
_history_skip_secrets() {
  emulate -L zsh -o extended_glob
  local name='(password|passwd|passphrase|token|secret|session|api[_-]#key|private[_-]#key)'
  [[ $1 == (#i)*${~name}[a-z0-9_]#=[\"\']#[^\$\"\'[:space:]]* ||
     $1 == (#i)*(bearer[[:space:]]|authorization:|cookie:|x-api-key:)* ]] && return 2
  return 0
}
autoload -Uz add-zsh-hook
add-zsh-hook zshaddhistory _history_skip_secrets
