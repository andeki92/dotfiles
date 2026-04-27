# cbox config — parse .cbox.toml in a project directory.
# Returns a normalized JSON document on stdout. Falls back to defaults if
# no .cbox.toml exists or parsing fails.

cbox::_config_defaults() {
  cat <<'JSON'
{
  "firewall": { "allow": [] },
  "env":      { "files": ["default"] },
  "mise":     { "install": true },
  "mounts":   { "extra": [] }
}
JSON
}

cbox::config_load() {
  local repo_root="${1:?repo_root}"
  local toml="${repo_root}/.cbox.toml"
  if [[ ! -f "$toml" ]]; then
    cbox::_config_defaults
    return
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    cbox::log_err "python3 required to parse .cbox.toml; using defaults"
    cbox::_config_defaults
    return
  fi
  local parsed
  parsed=$(python3 - "$toml" <<'PY'
import json, sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
defaults = {
  "firewall": {"allow": []},
  "env":      {"files": ["default"]},
  "mise":     {"install": True},
  "mounts":   {"extra": []},
}
for section, default_section in defaults.items():
    src = data.get(section, {}) or {}
    for k, v in default_section.items():
        if k not in src:
            src[k] = v
    data[section] = src
print(json.dumps(data))
PY
  ) || { cbox::log_err "failed to parse $toml; using defaults"; cbox::_config_defaults; return; }
  printf '%s\n' "$parsed"
}
