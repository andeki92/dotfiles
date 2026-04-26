# cbox common helpers — sourced by bin/cbox and lib/*.sh.
# Pure functions only. No I/O outside log_*.

# Crockford base32 alphabet without ambiguous chars (no 0,O,1,I,L,U).
readonly _CBOX_ALPHABET='23456789abcdefghjkmnpqrstvwxyz'

cbox::id() {
  local i out=''
  for i in 1 2 3 4 5 6; do
    local n
    n=$(( $(od -An -N1 -tu1 /dev/urandom | tr -d ' ') % ${#_CBOX_ALPHABET} ))
    out+="${_CBOX_ALPHABET:$n:1}"
  done
  printf '%s\n' "$out"
}

cbox::repo_slug() {
  local path="${1:?cbox::repo_slug requires a path}"
  local name
  name=$(basename "$path")
  # Lowercase, underscores → hyphens, strip non-alphanumeric-hyphen.
  printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | sed 's/[^a-z0-9-]//g'
}

# Color is opt-in: only when stderr is a TTY and NO_COLOR is unset.
_cbox_color() {
  if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    printf '%s' "$1"
  fi
}

cbox::log()      { printf '%scbox:%s %s\n' "$(_cbox_color $'\033[36m')" "$(_cbox_color $'\033[0m')" "$*" >&2; }
cbox::log_err()  { printf '%scbox:%s %s\n' "$(_cbox_color $'\033[31m')" "$(_cbox_color $'\033[0m')" "$*" >&2; }
cbox::log_warn() { printf '%scbox:%s %s\n' "$(_cbox_color $'\033[33m')" "$(_cbox_color $'\033[0m')" "$*" >&2; }
cbox::log_ok()   { printf '%scbox:%s %s\n' "$(_cbox_color $'\033[32m')" "$(_cbox_color $'\033[0m')" "$*" >&2; }

cbox::require_cmd() {
  local cmd="${1:?cbox::require_cmd requires a command name}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    cbox::log_err "required command not found: ${cmd}"
    return 1
  fi
}

# Resolve $HOME-aware paths used by the rest of the harness.
cbox::home()       { printf '%s\n' "${CBOX_HOME:-$HOME/.cbox}"; }
cbox::state_dir()  { printf '%s\n' "${CBOX_STATE_DIR:-$(cbox::home)/state}"; }
cbox::worktrees_dir() { printf '%s\n' "$(cbox::home)/worktrees"; }
cbox::config_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/cbox"; }
