#!/usr/bin/env bash
# One-shot post-stow setup: link the platform-specific git config,
# then report (via git itself) which email resolves in which context.
# Rules are discovered dynamically from the config file, not hardcoded.
# Safe to re-run any number of times.

set -euo pipefail

GIT_CONFIG_DIR="$HOME/.config/git"
PLATFORM_LINK="$GIT_CONFIG_DIR/config-platform"
LOCAL_DIR="$GIT_CONFIG_DIR/local"

if [[ ! -d "$GIT_CONFIG_DIR" ]]; then
  echo "$GIT_CONFIG_DIR does not exist — did you run \`stow -R .\` first?" >&2
  exit 1
fi

case "$(uname)" in
  Darwin)
    target="$GIT_CONFIG_DIR/config-macos"
    ;;
  Linux)
    if [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]] || \
       [[ "$(uname -r)" =~ [Mm]icrosoft ]] || \
       [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
      target="$GIT_CONFIG_DIR/config-wsl"
    else
      target="$GIT_CONFIG_DIR/config-linux"
    fi
    ;;
  *)
    echo "Unsupported platform: $(uname)" >&2
    exit 1
    ;;
esac

if [[ ! -f "$target" ]]; then
  echo "Expected platform config not found: $target" >&2
  exit 1
fi

ln -sf "$target" "$PLATFORM_LINK"
echo "Linked $PLATFORM_LINK -> $target"
echo

# --- Discover ONLY conditional includeIf rules (gitdir-based) dynamically.
# Unconditional include.path entries deliberately excluded from this list —
# they're not "conditions", they just contribute to <default> below, which
# we always test directly via real git resolution regardless of whether
# such an entry exists.
rules="$(git config -f "$target" --get-regexp '^includeif\..*\.path$' || true)"

labels=()
dirs=()
local_paths=()

if [[ -n "$rules" ]]; then
  while IFS= read -r line; do
    key="${line%% *}"
    raw_path="${line#* }"
    expanded_path="${raw_path/#\~/$HOME}"
    local_paths+=("$expanded_path")

    condition="${key#includeif.}"
    condition="${condition%.path}"
    gd="${condition#gitdir:}"
    gd="${gd#gitdir/i:}"
    gd_expanded="${gd/#\~/$HOME}"
    labels+=("$gd")
    dirs+=("$gd_expanded")
  done <<< "$rules"
fi

# Also collect any unconditional include.path targets, purely so we can
# make sure their local files exist too (they still feed into <default>).
unconditional_rules="$(git config -f "$target" --get-regexp '^include\.path$' || true)"
if [[ -n "$unconditional_rules" ]]; then
  while IFS= read -r line; do
    raw_path="${line#* }"
    expanded_path="${raw_path/#\~/$HOME}"
    local_paths+=("$expanded_path")
  done <<< "$unconditional_rules"
fi

# --- Ensure every referenced local identity file exists ---
mkdir -p "$LOCAL_DIR"
stubbed=()
for f in "${local_paths[@]}"; do
  if [[ -n "$f" ]] && [[ ! -f "$f" ]]; then
    mkdir -p "$(dirname "$f")"
    cat > "$f" <<'EOF'
[user]
	email = # TODO: fill in and remove this comment
EOF
    stubbed+=("$f")
  fi
done
if [[ ${#stubbed[@]} -gt 0 ]]; then
  echo "⚠️  Created missing local identity file(s) (fill these in):" >&2
  for f in "${stubbed[@]}"; do echo "   - $f" >&2; done
  echo >&2
fi

# --- Ask git itself what email resolves in each context ---
report_context() {
  local label="$1" dir="$2"
  local created_dir=0 created_repo=0

  if [[ -n "$dir" ]]; then
    [[ -d "$dir" ]] || { mkdir -p "$dir"; created_dir=1; }
    [[ -d "$dir/.git" ]] || { git init -q "$dir"; created_repo=1; }
  else
    dir="$(mktemp -d)"
    created_dir=1 # tmp dir, deliberately outside any gitdir pattern
  fi

  local output rc=0
  output="$(git -C "$dir" config --show-origin --get user.email 2>&1)" || rc=$?

  if [[ $rc -eq 0 ]]; then
    local origin="${output%%$'\t'*}"
    local email="${output#*$'\t'}"
    origin="${origin#file:}"
    printf "  %-22s -> %-35s [%s]\n" "$label" "$email" "$origin"
  else
    printf "  %-22s -> (unresolved) %s\n" "$label" "$output"
  fi

  [[ $created_repo -eq 1 ]] && rm -rf "$dir/.git"
  [[ $created_dir -eq 1 ]] && rm -rf "$dir"
}

echo "Identity routing (as resolved by \`git config\`, target: $target):"
# <default> is always tested — regardless of whether $target contains an
# unconditional include — because the base ~/.gitconfig may set user.email
# on its own, with or without an override further down the include chain.
report_context "<default>" ""
for i in "${!labels[@]}"; do
  report_context "${labels[$i]}" "${dirs[$i]}"
done
