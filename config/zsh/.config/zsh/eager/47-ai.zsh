# AI coding agents: Claude Code launchers and short names for the others.
#
# Defined with `function name { }`, not `name() { }`: an alias of the same
# name (the old `alias c='clear'`, say) survives `rl` and would rewrite a
# `c() { }` definition into `clear() { }`. The unalias clears one anyway.
unalias c claude oc 2>/dev/null

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
function c {
  local -a flags=(--model opus --effort high --advisor fable)
  local mode="CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=${CLAUDE_CODE_EXPERIMENTAL_CODE_MODE:-1}"
  "${_claude_strip[@]}" "$mode" DO_NOT_TRACK=0 claude "${flags[@]}" "$@"
}

# opencode
alias oc='opencode'
