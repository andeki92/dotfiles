#!/usr/bin/env bash
#
# block-bash-file-edits.sh — Claude Code PreToolUse guard for the Bash tool.
#
# Purpose: stop Claude from *editing files through the shell* (sed -i, perl -i,
# heredoc/echo redirects, inline python/node write-scripts) when it should be
# using the Write / Edit tools instead. A shell write skips everything the real
# tools give you: a reviewable diff, file-history checkpointing (/rewind), and
# the PostToolUse linters in ./linters/. `sed -i` does none of that.
#
# Wired in ~/.claude/settings.json as a PreToolUse hook with matcher "Bash".
# Claude pipes the tool call as JSON on stdin. Contract (same shape the linters
# use, so the two read consistently):
#   exit 0 -> allow; the command continues through the normal permission flow
#   exit 2 -> block; stderr is fed back to the model as the actionable reason
#
# Design bias: HIGH PRECISION. It is better to miss a sneaky write than to block
# legitimate shell work, so it only fires on unambiguous edit idioms:
#   1. in-place stream editors (sed -i, perl -pi, ruby -i, gawk -i inplace)
#   2. file-content writes — redirects/tee/heredocs targeting a *source-looking*
#      path that is not a temp/scratch location
#   3. inline interpreter write-scripts (python -c / node -e that write files)
# Read-only sed/awk/grep, redirects to /tmp or /dev/null, and capturing output
# to data files (.log/.csv) all pass through untouched.
#
# Escape hatch — for the rare intentional shell write (generated artifact, etc.):
#   set CLAUDE_ALLOW_BASH_WRITE=1, or append the token '# claude-allow-write'.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0   # no jq -> degrade to no-op, never block

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Explicit opt-out for a deliberately-intended shell write.
[ "${CLAUDE_ALLOW_BASH_WRITE:-}" = "1" ] && exit 0
case "$cmd" in
  *'# claude-allow-write'*) exit 0 ;;
esac

block() {
  # $1 = short, specific reason ("what we matched")
  cat >&2 <<EOF
BLOCKED: $1

Edit files with the Edit / Write tools, not the Bash tool. They produce a
reviewable diff, respect checkpointing (/rewind), and run the edit-time linters
— none of which happen for a shell write.

If this shell write is genuinely intended (generated artifact, scratch file,
piping into a build output, etc.), re-run with CLAUDE_ALLOW_BASH_WRITE=1 in the
environment, or append the token '# claude-allow-write' to the command.
EOF
  exit 2
}

# --- Helpers ----------------------------------------------------------------

# A redirect/tee/heredoc target counts as "temp/scratch" — always allowed.
# SC2016: the '$TMPDIR' patterns match the *literal, un-expanded* text as it
# appears in the command string; we deliberately do not want expansion here.
is_temp_target() {
  # shellcheck disable=SC2016
  case "$1" in
    /dev/null|/dev/stdout|/dev/stderr|/dev/fd/*|'&'[0-9]*) return 0 ;;
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) return 0 ;;
    *scratchpad*|*/.git/*) return 0 ;;
    '$TMPDIR'*|'${TMPDIR}'*|'$GITHUB_OUTPUT'|'$GITHUB_ENV'|'$GITHUB_STEP_SUMMARY') return 0 ;;
    '('*) return 0 ;;   # process substitution >(...)
    *) return 1 ;;
  esac
}

# Does a target path look like a source/config file we'd want edited via Edit?
src_ext_re='\.(js|jsx|ts|tsx|mjs|cjs|py|pyi|go|rs|rb|php|java|kt|kts|scala|swift|c|h|cc|cpp|cxx|hpp|cs|sh|bash|zsh|fish|lua|vim|el|yaml|yml|toml|ini|cfg|conf|json|json5|jsonc|md|mdx|rst|adoc|html|htm|xml|css|scss|sass|less|styl|vue|svelte|sql|graphql|gql|proto|tf|hcl|gradle|properties|env|zshrc|bashrc|gitignore|gitconfig)$'
src_name_re='^(Makefile|Dockerfile|Gemfile|Rakefile|Brewfile|Procfile|Vagrantfile|\.gitignore|\.gitconfig|\.zshrc|\.bashrc|\.env|\.editorconfig|\.stowrc)$'
looks_like_source() {
  local base="${1##*/}"
  printf '%s' "$base" | grep -Eiq "$src_ext_re" && return 0
  printf '%s' "$base" | grep -Eq  "$src_name_re" && return 0
  return 1
}

# Strip heredoc *bodies* — the lines between `<<DELIM` and the closing DELIM.
# Content fed to a command's stdin (a commit message in `git commit -F - <<EOF`,
# a PR body in `gh pr create <<EOF`) is data, not shell, and must never be
# parsed for redirects or edit idioms — otherwise prose like "Latte <-> Mocha"
# reads as `> Mocha`. The `<<DELIM` operator itself is kept, so a genuine
# `cat > file <<EOF` write is still detected via its real `>` redirect below.
strip_heredoc_bodies() {
  local line delim='' inhd=0 out=''
  local hd_re='<<-?[[:space:]]*["'\'']?([A-Za-z_][A-Za-z0-9_]*)'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$inhd" = 1 ]; then
      local trimmed="${line#"${line%%[![:space:]]*}"}"   # ltrim (covers <<- tabs)
      [ "$trimmed" = "$delim" ] && inhd=0
      continue
    fi
    out+="$line"$'\n'
    # A here-string (<<<) has no body; don't mistake it for a heredoc.
    if [ "${line#*'<<<'}" = "$line" ] && [[ "$line" =~ $hd_re ]]; then
      delim="${BASH_REMATCH[1]}"
      inhd=1
    fi
  done < <(printf '%s' "$1")
  printf '%s' "$out"
}

# Blank out the *contents* of quoted strings (and their quotes) so prose inside
# echo / commit-message / -m arguments — "done -> next", "x > y", "use sed -i" —
# is never parsed as a redirect or edit idiom. Real redirects and idioms live
# OUTSIDE quotes and survive untouched. Escapes are handled leniently; per the
# precision bias, a missed block beats a false one.
strip_quoted() {
  local s="$1" out='' q='' ch i n=${#1}
  for (( i = 0; i < n; i++ )); do
    ch="${s:i:1}"
    if [ -n "$q" ]; then
      [ "$ch" = "$q" ] && q=''
      continue
    fi
    if [ "$ch" = "'" ] || [ "$ch" = '"' ]; then
      q="$ch"
      continue
    fi
    out+="$ch"
  done
  printf '%s' "$out"
}

# From here on, match against the de-data'd command: heredoc bodies removed and
# quoted-string contents blanked, leaving only the shell skeleton.
cmd="$(strip_heredoc_bodies "$cmd")"
cmd="$(strip_quoted "$cmd")"

# --- 1. In-place stream editors. Near-zero false positives. -----------------
# sed -i / --in-place / -i.bak / -ri ; perl -i / -pi ; ruby -i ; gawk -i inplace.
# `[^|;&<>]*` keeps the flag on the SAME simple command as the tool name, so a
# downstream `| sed` in a pipeline isn't mis-attributed.
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])g?sed[^|;&<>]*([[:space:]]-[a-zA-Z]*i([.=[:space:]]|$)|[[:space:]]--in-place)'; then
  block "in-place edit via 'sed -i' (use Edit instead)"
fi
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])perl[^|;&<>]*[[:space:]]-[a-zA-Z]*i([.=[:space:]]|$)'; then
  block "in-place edit via 'perl -i' (use Edit instead)"
fi
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])ruby[^|;&<>]*[[:space:]]-[a-zA-Z]*i([.=[:space:]]|$)'; then
  block "in-place edit via 'ruby -i' (use Edit instead)"
fi
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])g?awk[^|;&<>]*-i[[:space:]]+inplace|inplace=1'; then
  block "in-place edit via 'awk -i inplace' (use Edit instead)"
fi

# --- 2. Inline interpreter write-scripts. -----------------------------------
# python/node/ruby/perl invoked with inline code (-c/-e) that writes a file or
# does in-place editing. Running a real *.py/*.js script is untouched; only the
# inline form combined with a write indicator trips this.
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_/])(python[0-9.]*|node|deno|bun|ruby|perl)[^|;&]*[[:space:]]-(c|e)([[:space:]]|=|")'; then
  if printf '%s' "$cmd" | grep -Eq "open\([^)]*['\"][wax]b?\+?['\"]|\.write_text\(|\.writelines?\(|\.write\(|writeFileSync|fs\.writeFile|fileinput[^;]*inplace[[:space:]]*=[[:space:]]*True|>[[:space:]]*open\("; then
    block "inline interpreter writing a file (use Write/Edit instead)"
  fi
fi

# --- 3. File-content writes: redirects, tee, heredocs. ----------------------
# Pull every redirect target (`> x`, `>> x`) off the command. A heredoc (`<<`)
# lowers the bar: any non-temp target is a file-write. Otherwise we only fire
# when the target *looks like source* — so `curl > /tmp/x`, `cmd > out.log`,
# and `echo "a > b"` (target `b`, no extension) all pass.
has_heredoc=0
case "$cmd" in *'<<'*) has_heredoc=1 ;; esac

while IFS= read -r raw; do
  [ -n "$raw" ] || continue
  target="${raw##*>}"                               # strip leading > / >>
  target="${target#"${target%%[![:space:]]*}"}"     # ltrim whitespace
  [ -n "$target" ] || continue
  is_temp_target "$target" && continue
  if [ "$has_heredoc" = 1 ]; then
    block "heredoc writing a file ('$target' — use Write instead)"
  fi
  if looks_like_source "$target"; then
    block "redirect writing a source file ('$target' — use Write/Edit instead)"
  fi
done < <(printf '%s' "$cmd" | grep -oE '>>?[[:space:]]*[^[:space:]|;&<>()]+' || true)

# tee writing a source-looking file (tee's whole job is to write files).
tee_target="$(printf '%s' "$cmd" | grep -oE '(^|[|[:space:]])tee([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[^[:space:]|;&]+' | grep -oE '[^[:space:]|;&]+$' || true)"
if [ -n "$tee_target" ] && ! is_temp_target "$tee_target"; then
  if [ "$has_heredoc" = 1 ] || looks_like_source "$tee_target"; then
    block "file write via 'tee $tee_target' (use Write instead)"
  fi
fi

exit 0
