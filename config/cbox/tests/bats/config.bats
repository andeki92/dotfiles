#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/setup'
  _cbox_test_setup
  source "${CBOX_LIB}/common.sh"
  source "${CBOX_LIB}/config.sh"
  CFG_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "${CFG_DIR:-}"
  [[ -n "${CBOX_TMP:-}" ]] && rm -rf "${CBOX_TMP}"
}

@test "cbox::config_load returns defaults when no .cbox.toml exists" {
  result=$(cbox::config_load "$CFG_DIR")
  [[ "$(echo "$result" | jq -r '.firewall.allow | length')" == "0" ]]
  [[ "$(echo "$result" | jq -r '.env.files | length')" == "1" ]]
  [[ "$(echo "$result" | jq -r '.env.files[0]')" == "default" ]]
  [[ "$(echo "$result" | jq -r '.mise.install')" == "true" ]]
  [[ "$(echo "$result" | jq -r '.mounts.extra | length')" == "0" ]]
}

@test "cbox::config_load reads firewall allows" {
  cat > "$CFG_DIR/.cbox.toml" <<'EOF'
[firewall]
allow = ["developers.strava.com", "registry.docker.io"]
EOF
  result=$(cbox::config_load "$CFG_DIR")
  [[ "$(echo "$result" | jq -r '.firewall.allow | length')" == "2" ]]
  [[ "$(echo "$result" | jq -r '.firewall.allow[0]')" == "developers.strava.com" ]]
}

@test "cbox::config_load reads env files list" {
  cat > "$CFG_DIR/.cbox.toml" <<'EOF'
[env]
files = ["default", "homelab"]
EOF
  result=$(cbox::config_load "$CFG_DIR")
  [[ "$(echo "$result" | jq -r '.env.files | length')" == "2" ]]
  [[ "$(echo "$result" | jq -r '.env.files[1]')" == "homelab" ]]
}

@test "cbox::config_load reads mise.install = false" {
  cat > "$CFG_DIR/.cbox.toml" <<'EOF'
[mise]
install = false
EOF
  result=$(cbox::config_load "$CFG_DIR")
  [[ "$(echo "$result" | jq -r '.mise.install')" == "false" ]]
}
