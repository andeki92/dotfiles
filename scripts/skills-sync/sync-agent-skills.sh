#!/usr/bin/env bash
#
# sync-agent-skills.sh
#
# Mirrors the skills/ of every *enabled* Claude Code plugin into
# ~/.agents/skills as symlinks, so other agent harnesses can use them.
#
# - Ownership-tracked: keeps a manifest of what it created, so it only ever
#   adds/removes entries it owns and never touches anything else living in
#   ~/.agent/skills.
# - Idempotent: safe to run constantly (e.g. from a launchd watcher).
# - Self-healing: a disabled plugin's link is removed on the next run; a
#   dangling link (source path gone) is just treated as "needs relinking".
#
# Requires: bash >= 4, jq, the `claude` CLI on PATH.

set -euo pipefail
shopt -s nullglob

if ((BASH_VERSINFO[0] < 4)); then
  echo "sync-agent-skills: needs bash >= 4 (macOS ships 3.2) — try: brew install bash" >&2
  exit 1
fi

SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agents/skills}"
STATE_DIR="${AGENT_SKILLS_STATE_DIR:-$HOME/.agents/.skills-sync-state}"
MANIFEST="$STATE_DIR/manifest.json"
LOCK_DIR="$STATE_DIR/sync.lock.d"
TAG="sync-agent-skills"

mkdir -p "$SKILLS_DIR" "$STATE_DIR"

# Prevent overlapping runs (e.g. a launchd watch fire + a manual `run`).
# mkdir is atomic on any POSIX filesystem — no external lock tool needed
# (macOS doesn't ship `flock`).
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "$TAG: another run (pid $old_pid) is already in progress — skipping" >&2
    exit 0
  fi
  echo "$TAG: found a stale lock (owner no longer running) — clearing it" >&2
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || { echo "$TAG: could not acquire lock" >&2; exit 1; }
fi
echo $$ > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

# CLAUDE_BIN lets you pin the real binary explicitly (e.g. if `claude` is a
# shell function/alias in your interactive shell — those aren't visible here,
# launchd/cron never source your rc files). Find it with:
#   (unset -f claude 2>/dev/null; command -v claude)
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"

command -v "$CLAUDE_BIN" >/dev/null 2>&1 || { echo "$TAG: '$CLAUDE_BIN' not found — set CLAUDE_BIN to its real path" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "$TAG: 'jq' is required" >&2; exit 1; }

plugin_json="$("$CLAUDE_BIN" plugin list --json 2>/dev/null)" || {
  echo "$TAG: 'claude plugin list --json' failed" >&2
  exit 1
}

# ---- Resolve: enabled plugins' installPaths -> individual skill dirs ----
declare -A desired   # skill_name -> resolved source path

while IFS= read -r install_path; do
  [[ -n "$install_path" && -d "$install_path/skills" ]] || continue
  # Search at any depth — some plugins group skills under category
  # subdirectories (skills/engineering/foo/SKILL.md), not just skills/foo/.
  while IFS= read -r -d '' skill_md; do
    skill_dir="$(dirname "$skill_md")"
    name="$(basename "$skill_dir")"
    src="$skill_dir"
    if [[ -n "${desired[$name]:-}" && "${desired[$name]}" != "$src" ]]; then
      echo "$TAG: WARNING skill name collision on '$name' — keeping '${desired[$name]}', ignoring '$src'" >&2
      continue
    fi
    desired[$name]="$src"
  done < <(find "$install_path/skills" -iname 'SKILL.md' -print0)
done < <(jq -r '.[] | select(.enabled == true) | .installPath' <<<"$plugin_json")

# ---- Load previous manifest (what this script owns) ----
declare -A previous
if [[ -f "$MANIFEST" ]]; then
  while IFS=$'\t' read -r name src; do
    [[ -n "$name" ]] && previous[$name]="$src"
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$MANIFEST")
fi

# ---- Remove links this script owns that are no longer desired ----
for name in "${!previous[@]}"; do
  if [[ -z "${desired[$name]:-}" ]]; then
    link="$SKILLS_DIR/$name"
    if [[ -L "$link" ]]; then
      rm -f "$link"
      echo "$TAG: removed '$name' (plugin disabled/uninstalled)"
    fi
  fi
done

# ---- Create/update desired links ----
for name in "${!desired[@]}"; do
  link="$SKILLS_DIR/$name"
  target="${desired[$name]}"

  if [[ -e "$link" && ! -L "$link" ]]; then
    echo "$TAG: WARNING '$link' exists and isn't a symlink this script manages — skipping" >&2
    continue
  fi

  current=""
  [[ -L "$link" ]] && current="$(readlink "$link")"

  if [[ "$current" != "$target" ]]; then
    ln -sfn "$target" "$link"
    echo "$TAG: linked '$name' -> $target"
  fi
done

# ---- Persist manifest (only entries this run considers owned) ----
tmp_manifest="$(mktemp "$STATE_DIR/manifest.XXXXXX.json")"
{
  for name in "${!desired[@]}"; do
    jq -n --arg k "$name" --arg v "${desired[$name]}" '{($k): $v}'
  done
} | jq -s 'add // {}' > "$tmp_manifest"
mv "$tmp_manifest" "$MANIFEST"

echo "$TAG: done — ${#desired[@]} skill(s) linked in $SKILLS_DIR"
