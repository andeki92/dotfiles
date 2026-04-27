#!/usr/bin/env bash
# Find and optionally remove broken symlinks at the top level of $HOME and
# $HOME/.config — relics of previous dotfiles layouts (~/dotfiles/, etc.) and
# stow packages that have since been removed.
#
# Usage:
#   scripts/clean-stale-symlinks.sh           # dry-run (default)
#   scripts/clean-stale-symlinks.sh --apply   # actually delete
#
# Skipped by name (managed externally, may legitimately be temporarily broken):
#   .nix-profile

set -euo pipefail

APPLY=0
case "${1:-}" in
  --apply) APPLY=1 ;;
  ""|--dry-run) APPLY=0 ;;
  -h|--help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown arg: $1" >&2
    exit 2
    ;;
esac

SKIP_NAMES=( ".nix-profile" )

is_skipped() {
  local name
  name=$(basename "$1")
  for skip in "${SKIP_NAMES[@]}"; do
    [[ "$name" == "$skip" ]] && return 0
  done
  return 1
}

scan() {
  local dir="$1"
  find -L "$dir" -maxdepth 1 -type l 2>/dev/null
}

mapfile -t candidates < <(
  scan "$HOME/.config"
  scan "$HOME"
)

broken=()
skipped=()
for link in "${candidates[@]}"; do
  if is_skipped "$link"; then
    skipped+=( "$link" )
  else
    broken+=( "$link" )
  fi
done

if [[ ${#skipped[@]} -gt 0 ]]; then
  echo "Skipping (excluded by name):"
  for link in "${skipped[@]}"; do
    printf '  %s -> %s\n' "$link" "$(readlink "$link")"
  done
  echo
fi

if [[ ${#broken[@]} -eq 0 ]]; then
  echo "No removable broken symlinks found at top level of \$HOME or \$HOME/.config."
  exit 0
fi

echo "Found ${#broken[@]} broken symlink(s):"
for link in "${broken[@]}"; do
  printf '  %s -> %s\n' "$link" "$(readlink "$link")"
done

if [[ $APPLY -eq 0 ]]; then
  echo
  echo "Dry-run. Re-run with --apply to remove these."
  exit 0
fi

echo
echo "Removing..."
for link in "${broken[@]}"; do
  rm -v "$link"
done
echo "Done."
