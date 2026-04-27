# cbox secrets — assemble --env-file arguments from env.d/{name}.env(.sops).
# Decrypted plaintext lives in a per-PID tmpfs dir; relies on container
# tmpfs cleanup (--rm) for security since we don't actively delete.

cbox::secrets_env_args() {
  local cfg_dir="$(cbox::config_dir)/env.d"
  local out_dir="${TMPDIR:-/tmp}/cbox-env-$$"
  mkdir -p "$out_dir"
  chmod 700 "$out_dir"
  for name in "$@"; do
    local plain="${cfg_dir}/${name}.env"
    local enc="${cfg_dir}/${name}.env.sops"
    if [[ -f "$enc" ]]; then
      cbox::require_cmd sops || return 1
      local target="${out_dir}/${name}.env"
      if ! sops -d "$enc" > "$target" 2>/dev/null; then
        cbox::log_err "failed to decrypt $enc — is your age key configured?"
        return 1
      fi
      printf -- '--env-file=%s\n' "$target"
    elif [[ -f "$plain" ]]; then
      printf -- '--env-file=%s\n' "$plain"
    elif [[ "$name" == "default" ]]; then
      :  # default is optional — silent skip
    else
      cbox::log_err "env file '${name}' not found in ${cfg_dir} (.env or .env.sops)"
      return 1
    fi
  done
}
