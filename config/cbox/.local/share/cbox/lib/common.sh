# cbox common helpers — sourced by bin/cbox and lib/*.sh.
# Pure functions only. No I/O outside log_*.
# Color decision is made at source time; redirecting stderr after sourcing won't disable colors.

# Crockford base32 alphabet without ambiguous chars (no 0,O,1,I,L,U).
readonly _CBOX_ALPHABET='23456789abcdefghjkmnpqrstvwxyz'

# Color is opt-in: only when stderr is a TTY and NO_COLOR is unset.
# Decided once at source time so log_* are single printf calls (no per-call subshells).
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  readonly _CBOX_C_RED=$'\033[31m'
  readonly _CBOX_C_GREEN=$'\033[32m'
  readonly _CBOX_C_YELLOW=$'\033[33m'
  readonly _CBOX_C_CYAN=$'\033[36m'
  readonly _CBOX_C_RESET=$'\033[0m'
else
  readonly _CBOX_C_RED='' _CBOX_C_GREEN='' _CBOX_C_YELLOW='' _CBOX_C_CYAN='' _CBOX_C_RESET=''
fi

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
  name=$(printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | sed 's/[^a-z0-9-]//g')
  # Strip leading dashes so the slug can't be misread as a CLI option (e.g. by `git branch`).
  while [[ "$name" == -* ]]; do
    name="${name#-}"
  done
  # Empty after sanitising? Use a safe fallback.
  if [[ -z "$name" ]]; then
    name='repo'
  fi
  # Cap length so a long directory name doesn't bleed into 200-char branch names.
  printf '%s\n' "${name:0:40}"
}

cbox::log()      { printf '%scbox:%s %s\n' "$_CBOX_C_CYAN"   "$_CBOX_C_RESET" "$*" >&2; }
cbox::log_err()  { printf '%scbox:%s %s\n' "$_CBOX_C_RED"    "$_CBOX_C_RESET" "$*" >&2; }
cbox::log_warn() { printf '%scbox:%s %s\n' "$_CBOX_C_YELLOW" "$_CBOX_C_RESET" "$*" >&2; }
cbox::log_ok()   { printf '%scbox:%s %s\n' "$_CBOX_C_GREEN"  "$_CBOX_C_RESET" "$*" >&2; }

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
