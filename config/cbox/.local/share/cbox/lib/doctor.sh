# cbox doctor — 16 host health checks.
# Sourced by bin/cbox. Requires: common.sh, engine.sh, proxy.sh, config.sh.
#
# Public function: cbox::doctor_run
#   Returns 0 if all checks pass (warnings are non-fatal).
#   Returns 1 if any FAIL was recorded.

# ---- Private helpers -----------------------------------------------------------

cbox::_check_ok()   { cbox::log_ok  "  $1"; }
cbox::_check_warn() { cbox::log_warn "  $1"; CBOX_DOCTOR_WARN=1; }
cbox::_check_fail() { cbox::log_err  "  $1"; CBOX_DOCTOR_FAIL=1; }

# _semver_ge <actual> <minimum>
# Returns 0 if actual >= minimum (compares first two components only).
cbox::_semver_ge() {
  local actual="$1" min="$2"
  local amaj amin bmaj bmin
  amaj="${actual%%.*}"; rest="${actual#*.}"; amin="${rest%%.*}"
  bmaj="${min%%.*}";    rest="${min#*.}";    bmin="${rest%%.*}"
  # Strip non-numeric suffixes.
  amaj="${amaj//[^0-9]/}"; amin="${amin//[^0-9]/}"
  bmaj="${bmaj//[^0-9]/}"; bmin="${bmin//[^0-9]/}"
  if   (( amaj > bmaj )); then return 0
  elif (( amaj < bmaj )); then return 1
  elif (( amin >= bmin )); then return 0
  else return 1
  fi
}

# ---- Public function -----------------------------------------------------------

cbox::doctor_run() {
  CBOX_DOCTOR_FAIL=0
  CBOX_DOCTOR_WARN=0

  cbox::log "checking host"

  # ------------------------------------------------------------------
  # 1. Container engine on PATH
  # ------------------------------------------------------------------
  local _cli
  _cli=$(cbox::engine_cli 2>/dev/null) || _cli=""
  if [[ -z "$_cli" ]]; then
    cbox::_check_fail "cannot determine container engine (unsupported OS?)"
  elif ! command -v "$_cli" >/dev/null 2>&1; then
    if [[ "$(uname -s)" == Darwin ]]; then
      cbox::_check_fail "${_cli} not found — install: https://github.com/apple/container/releases"
    else
      cbox::_check_fail "${_cli} not found — install: sudo apt install podman"
    fi
  else
    local _cli_ver
    _cli_ver=$("$_cli" --version 2>/dev/null | head -1 || true)
    cbox::_check_ok "${_cli} on PATH (${_cli_ver:-unknown version})"
  fi

  # ------------------------------------------------------------------
  # 2. Engine ready
  # ------------------------------------------------------------------
  if ! cbox::engine_ready 2>/dev/null; then
    if [[ "$(uname -s)" == Darwin ]]; then
      cbox::_check_fail "container system not running — run: container system start"
    else
      cbox::_check_fail "podman not ready — ensure rootful podman is installed and running"
    fi
  else
    cbox::_check_ok "engine ready"
  fi

  # ------------------------------------------------------------------
  # 3. tmux >= 3.0
  # ------------------------------------------------------------------
  if ! command -v tmux >/dev/null 2>&1; then
    if [[ "$(uname -s)" == Darwin ]]; then
      cbox::_check_fail "tmux not found — install: brew install tmux"
    else
      cbox::_check_fail "tmux not found — install: sudo apt install tmux"
    fi
  else
    local _tmux_raw _tmux_ver
    _tmux_raw=$(tmux -V 2>/dev/null || true)
    _tmux_ver="${_tmux_raw#tmux }"
    if cbox::_semver_ge "$_tmux_ver" "3.0"; then
      cbox::_check_ok "tmux ${_tmux_ver}"
    else
      if [[ "$(uname -s)" == Darwin ]]; then
        cbox::_check_fail "tmux ${_tmux_ver} < 3.0 — upgrade: brew install tmux"
      else
        cbox::_check_fail "tmux ${_tmux_ver} < 3.0 — upgrade: sudo apt install tmux"
      fi
    fi
  fi

  # ------------------------------------------------------------------
  # 4. fzf >= 0.40
  # ------------------------------------------------------------------
  if ! command -v fzf >/dev/null 2>&1; then
    cbox::_check_fail "fzf not found — install: mise install"
  else
    local _fzf_raw _fzf_ver
    _fzf_raw=$(fzf --version 2>/dev/null || true)
    _fzf_ver="${_fzf_raw%% *}"
    if cbox::_semver_ge "$_fzf_ver" "0.40"; then
      cbox::_check_ok "fzf ${_fzf_ver}"
    else
      cbox::_check_fail "fzf ${_fzf_ver} < 0.40 — upgrade: mise install"
    fi
  fi

  # ------------------------------------------------------------------
  # 5. squid present
  # ------------------------------------------------------------------
  if ! command -v squid >/dev/null 2>&1; then
    if [[ "$(uname -s)" == Darwin ]]; then
      cbox::_check_fail "squid not found — install: brew install squid"
    else
      cbox::_check_fail "squid not found — install: sudo apt install squid"
    fi
  else
    local _squid_ver
    _squid_ver=$(squid -v 2>&1 | head -1 || true)
    cbox::_check_ok "squid on PATH (${_squid_ver:-unknown version})"
  fi

  # ------------------------------------------------------------------
  # 6. gh CLI on PATH (warn-only)
  # ------------------------------------------------------------------
  if ! command -v gh >/dev/null 2>&1; then
    cbox::_check_warn "gh not found — PR creation inside cbox will fail (non-fatal)"
  else
    cbox::_check_ok "gh on PATH"
  fi

  # ------------------------------------------------------------------
  # 7. SSH_AUTH_SOCK set + socket exists
  # ------------------------------------------------------------------
  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    cbox::_check_fail "SSH_AUTH_SOCK not set — run: eval \$(ssh-agent) && ssh-add"
  elif [[ ! -S "$SSH_AUTH_SOCK" ]]; then
    cbox::_check_fail "SSH_AUTH_SOCK set but socket missing (${SSH_AUTH_SOCK}) — run: eval \$(ssh-agent)"
  else
    cbox::_check_ok "ssh-agent socket present"
  fi

  # ------------------------------------------------------------------
  # 8. GPG agent socket (only if commit.gpgsign = true AND gpg.format != ssh)
  # ------------------------------------------------------------------
  local _gpgsign _gpgformat
  _gpgsign=$(git config --global --get commit.gpgsign 2>/dev/null || true)
  _gpgformat=$(git config --global --get gpg.format 2>/dev/null || true)
  if [[ "$_gpgsign" == "true" && "$_gpgformat" != "ssh" ]]; then
    if ! command -v gpgconf >/dev/null 2>&1; then
      cbox::_check_fail "gpg signing enabled but gpgconf not installed — install gnupg or set gpg.format=ssh"
    else
      local _gpg_sock
      _gpg_sock=$(gpgconf --list-dirs agent-socket 2>/dev/null || true)
      if [[ -z "$_gpg_sock" || ! -S "$_gpg_sock" ]]; then
        cbox::_check_fail "gpg signing enabled but agent socket missing — run: gpgconf --launch gpg-agent"
      else
        cbox::_check_ok "gpg agent socket present"
      fi
    fi
  elif [[ "$_gpgsign" == "true" && "$_gpgformat" == "ssh" ]]; then
    cbox::_check_ok "ssh-key commit signing enabled (no gpg-agent needed)"
  fi
  # else: signing off, skip silently

  # ------------------------------------------------------------------
  # 9. ~/.gitconfig with user.email and user.name
  # ------------------------------------------------------------------
  if [[ ! -f "$HOME/.gitconfig" ]]; then
    cbox::_check_fail "~/.gitconfig not found — run: git config --global user.name '...' && git config --global user.email '...'"
  else
    local _git_name _git_email
    _git_name=$(git config --global --get user.name 2>/dev/null || true)
    _git_email=$(git config --global --get user.email 2>/dev/null || true)
    if [[ -z "$_git_name" || -z "$_git_email" ]]; then
      cbox::_check_fail "~/.gitconfig missing user.name or user.email — run: git config --global user.name '...' && git config --global user.email '...'"
    else
      cbox::_check_ok "git identity: ${_git_name} <${_git_email}>"
    fi
  fi

  # ------------------------------------------------------------------
  # 10. ~/.cache/mise writable
  # ------------------------------------------------------------------
  local _mise_cache="$HOME/.cache/mise"
  if [[ -e "$_mise_cache" && ! -w "$_mise_cache" ]]; then
    cbox::_check_fail "~/.cache/mise exists but is not writable — run: chmod u+w ${_mise_cache}"
  else
    # Doesn't exist yet (fine) or exists and is writable.
    cbox::_check_ok "~/.cache/mise writable (or absent)"
  fi

  # ------------------------------------------------------------------
  # 11. Dotfiles stowed: Containerfile present in config_dir
  # ------------------------------------------------------------------
  local _cfg_dir
  _cfg_dir=$(cbox::config_dir)
  if [[ ! -f "${_cfg_dir}/Containerfile" ]]; then
    cbox::_check_fail "Containerfile not found at ${_cfg_dir}/Containerfile — run: cd ~/.dotfiles && stow cbox"
  else
    cbox::_check_ok "dotfiles stowed (Containerfile present)"
  fi

  # ------------------------------------------------------------------
  # 12. Image cbox:latest present
  # ------------------------------------------------------------------
  if ! cbox::engine_image_exists "cbox:latest" 2>/dev/null; then
    cbox::_check_fail "image cbox:latest not found — run: cbox build"
  else
    cbox::_check_ok "image cbox:latest present"
  fi

  # ------------------------------------------------------------------
  # 13. Default allow-list present
  # ------------------------------------------------------------------
  local _default_list="${_cfg_dir}/allowlist.d/_default.txt"
  if [[ ! -f "$_default_list" ]]; then
    cbox::_check_fail "default allow-list missing: ${_default_list} — ensure dotfiles are stowed correctly"
  else
    cbox::_check_ok "default allow-list present"
  fi

  # ------------------------------------------------------------------
  # 14. Claude auth — at least one of:
  #       (a) ~/.cbox/oauth-token (mode 600), generated via `claude setup-token`
  #       (b) CLAUDE_CODE_OAUTH_TOKEN env var on host
  #       (c) ANTHROPIC_API_KEY env var on host
  #     Without one of these, every cbox session falls into Claude's
  #     first-run flow (theme picker + OAuth login) inside the container.
  # ------------------------------------------------------------------
  local _token_file
  _token_file="$(cbox::home)/oauth-token"
  if [[ -f "$_token_file" ]]; then
    local _mode
    _mode=$(stat -f '%Lp' "$_token_file" 2>/dev/null || stat -c '%a' "$_token_file" 2>/dev/null)
    if [[ "$_mode" != "600" ]]; then
      cbox::_check_warn "${_token_file} mode is ${_mode}; should be 600 (chmod 600 ${_token_file})"
    else
      cbox::_check_ok "Claude OAuth token configured (~/.cbox/oauth-token)"
    fi
  elif [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    cbox::_check_ok "Claude OAuth token configured (CLAUDE_CODE_OAUTH_TOKEN env)"
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    cbox::_check_ok "Anthropic API key configured (ANTHROPIC_API_KEY env)"
  else
    cbox::_check_fail "no Claude auth configured — run \`claude setup-token\` on host then save the output to ~/.cbox/oauth-token (chmod 600)"
  fi

  # ------------------------------------------------------------------
  # 15. sops + age key (only if *.sops files exist)
  # ------------------------------------------------------------------
  local _sops_files=()
  local _env_d="${_cfg_dir}/env.d"
  if [[ -d "$_env_d" ]]; then
    while IFS= read -r -d '' _f; do
      _sops_files+=("$_f")
    done < <(find "$_env_d" -name '*.sops' -print0 2>/dev/null)
  fi
  if (( ${#_sops_files[@]} > 0 )); then
    if ! command -v sops >/dev/null 2>&1; then
      cbox::_check_fail "sops files found but sops not on PATH — install sops"
    else
      local _age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
      if [[ -z "${SOPS_AGE_KEY_FILE:-}" && ! -f "$HOME/.config/sops/age/keys.txt" ]]; then
        cbox::_check_fail "sops files found but no age key — set SOPS_AGE_KEY_FILE or create ~/.config/sops/age/keys.txt"
      else
        cbox::_check_ok "sops + age key present"
      fi
    fi
  fi
  # else: skip silently

  # ------------------------------------------------------------------
  # 15. Squid config valid (only if state squid.conf exists)
  # ------------------------------------------------------------------
  local _squid_conf
  _squid_conf="$(cbox::state_dir)/squid.conf"
  if [[ -f "$_squid_conf" ]]; then
    if squid -k parse -f "$_squid_conf" >/dev/null 2>&1; then
      cbox::_check_ok "squid config valid"
    else
      cbox::_check_warn "squid config parse error — run: cbox proxy reload"
    fi
  fi
  # else: skip silently

  # ------------------------------------------------------------------
  # 16. Last-build timestamp
  # ------------------------------------------------------------------
  local _last_build
  _last_build="$(cbox::state_dir)/last-build"
  if [[ ! -f "$_last_build" ]]; then
    cbox::_check_warn "no record of last build (first run?)"
  elif [[ "${_cfg_dir}/Containerfile" -nt "$_last_build" ]]; then
    cbox::_check_warn "Containerfile newer than last build — run: cbox build"
  else
    cbox::_check_ok "image is up-to-date with Containerfile"
  fi

  # ------------------------------------------------------------------
  # 17. Proxy status (informational only)
  # ------------------------------------------------------------------
  if cbox::proxy_status >/dev/null 2>&1; then
    cbox::_check_ok "squid running"
  fi

  # ------------------------------------------------------------------
  # Summary
  # ------------------------------------------------------------------
  if (( CBOX_DOCTOR_FAIL )); then
    cbox::log_err "doctor: FAILED (see red items above)"
    return 1
  elif (( CBOX_DOCTOR_WARN )); then
    cbox::log_warn "doctor: warnings (non-fatal)"
    return 0
  else
    cbox::log_ok "doctor: all green"
    return 0
  fi
}
