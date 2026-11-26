# AI coding agents: Claude Code, Pi, and OpenCode launchers.
#
# Defined with `function name { }`, not `name() { }`: an alias of the same
# name (the old `alias c='clear'`, say) survives `rl` and would rewrite a
# `c() { }` definition into `clear() { }`. The unalias clears one anyway.
unalias c claude oc pi pi-unsafe 2>/dev/null

# claude — every session starts without your gitlab.com credential helper, the
# GIT_CONFIG_* trio eager/10-platform.zsh exports, so agents reach gitlab.com
# only through 0th's `1st`. `claude plugin ...` keeps it: adding and updating
# the private zeroth marketplace needs your glab login.
_claude_strip=(env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0)
function claude {
  [[ "${1:-}" == plugin ]] && { command claude "$@"; return; }
  "${_claude_strip[@]}" claude "$@"
}

# c — Claude Code with tracking on, so the flag-gated features DO_NOT_TRACK
# hides (/advisor among them) work, on the latest Opus at high effort with the
# latest Fable as advisor. Aliases, not version ids, so a new model needs no
# edit here. --effort is passed because Opus 5.5 and later ignore the
# top-level effortLevel setting and start at medium; the flag ranks below
# /effort, so a level picked mid-session still wins.
#
# Code Mode (experimental) is on by default (0th's ADR-050); a session started
# in it resumes only with it on. `CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=0 c` opts
# one launch out, for a session telemetry must trace: Code Mode won't start
# while CLAUDE_CODE_ENABLE_TELEMETRY is set.
#
# Workspace: plain `c` signs in with your /login, so it runs in the Console's
# Claude Code workspace. `c --sr` (first argument) runs in Security Research,
# the workspace with the Defense Access grant, through the Anthropic profile
# `ant auth login --profile security-research` wrote. A named profile ranks
# above /login; `/status` shows a Profile row when it is the one in use.
function c {
  local -a flags=(--model opus --effort high --advisor fable) profile=()
  if [[ "${1:-}" == --sr ]]; then
    shift
    profile=(ANTHROPIC_PROFILE=security-research)
  fi
  local mode="CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=${CLAUDE_CODE_EXPERIMENTAL_CODE_MODE:-1}"
  "${_claude_strip[@]}" "$mode" DO_NOT_TRACK=0 "${profile[@]}" claude "${flags[@]}" "$@"
}

# opencode
alias oc='opencode'

# Pi coding agent — sandboxed in Gondolin by default, self-updates pinned to repo.
# NO_ANON_PING=1 (alongside DO_NOT_TRACK=1) disables @plannotator/pi-extension's daily ping.
export PI_SELF_UPDATE_COMMAND="pi-self-update {packageName} {version} {installSpec}"

_pi_preflight_sandbox() {
  local kvm_dev="${PI_SANDBOX_KVM_DEVICE:-/dev/kvm}"
  if [[ "$OSTYPE" == linux* && "${PI_SANDBOX_ALLOW_EMULATION:-0}" != "1" ]]; then
    if [[ ! -r "$kvm_dev" || ! -w "$kvm_dev" ]]; then
      print -u2 "[pi] FATAL: Gondolin sandbox requires read/write access to $kvm_dev."
      if [[ " $(id -nG "$USER" 2>/dev/null) " == *" kvm "* ]]; then
        print -u2 "[pi] Your user IS in the kvm group, but this shell inherited old groups from its parent session (e.g. a long-running herdr server)."
        print -u2 "[pi] Fix: from a fresh WSL shell where \`id\` shows kvm, run: herdr server stop && herdr"
      else
        print -u2 "[pi] Fix: sudo usermod -aG kvm \"\$USER\" (then restart herdr / start a fresh login)."
      fi
      print -u2 "[pi] Refusing to start with host tools. Explicit escape hatch: pi-unsafe"
      return 2
    fi
  fi
  if [[ -n "${GONDOLIN_KRUN_RUNNER:-}" && ! -x "${GONDOLIN_KRUN_RUNNER}" ]]; then
    print -u2 "[pi] FATAL: GONDOLIN_KRUN_RUNNER is not executable: $GONDOLIN_KRUN_RUNNER"
    print -u2 "[pi] Refusing to start with host tools. Explicit escape hatch: pi-unsafe"
    return 2
  fi
  return 0
}

function pi {
  # Package/auth/metadata subcommands do not start a coding session or tools.
  case "${1:-}" in
    install|remove|uninstall|update|list|config|auth|mcp|-v|--version|-h|--help|--list-models)
      NO_ANON_PING=1 DO_NOT_TRACK="${DO_NOT_TRACK:-1}" \
        PI_SELF_UPDATE_COMMAND="pi-self-update {packageName} {version} {installSpec}" \
        command pi "$@"
      return $?
      ;;
  esac

  _pi_preflight_sandbox || return $?
  NO_ANON_PING=1 DO_NOT_TRACK="${DO_NOT_TRACK:-1}" \
    PI_SELF_UPDATE_COMMAND="pi-self-update {packageName} {version} {installSpec}" \
    PI_SANDBOX_UNSAFE=0 \
    command pi "$@"
}

# Explicit escape hatch: runs Pi directly on the host with NO Gondolin VM.
function pi-unsafe {
  print -u2 "========================================================================"
  print -u2 "WARNING: Starting Pi WITHOUT Gondolin sandbox (pi-unsafe)."
  print -u2 "Built-in tools have FULL host filesystem, credential, and network access."
  print -u2 "========================================================================"
  NO_ANON_PING=1 DO_NOT_TRACK="${DO_NOT_TRACK:-1}" \
    PI_SELF_UPDATE_COMMAND="pi-self-update {packageName} {version} {installSpec}" \
    PI_SANDBOX_UNSAFE=1 \
    command pi "$@"
}
