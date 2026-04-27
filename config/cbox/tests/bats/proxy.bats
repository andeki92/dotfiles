#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  load '../helpers/setup'
  _cbox_test_setup
  source "${CBOX_LIB}/common.sh"
  source "${CBOX_LIB}/state.sh"
  source "${CBOX_LIB}/proxy.sh"
  # Override config dir to a tmp area where we can stage allow-lists.
  export _CBOX_CONFIG_DIR_OVERRIDE="${CBOX_TMP}/cfg"
  mkdir -p "${_CBOX_CONFIG_DIR_OVERRIDE}/allowlist.d"
  cp "${CBOX_DOTFILES}/.config/cbox/squid.conf.template" "${_CBOX_CONFIG_DIR_OVERRIDE}/"
  cp "${CBOX_DOTFILES}/.config/cbox/allowlist.d/_default.txt" "${_CBOX_CONFIG_DIR_OVERRIDE}/allowlist.d/"
}

@test "cbox::proxy_render_config produces a non-empty squid.conf" {
  out="${CBOX_TMP}/squid.conf"
  cbox::proxy_render_config "$out" 3128
  [[ -s "$out" ]]
  grep -q "http_port 3128" "$out"
  grep -q "^acl _default dstdomain" "$out"
}

@test "cbox::proxy_render_config includes per-project allow-lists" {
  printf '.example.com\n' > "${_CBOX_CONFIG_DIR_OVERRIDE}/allowlist.d/myproject.txt"
  out="${CBOX_TMP}/squid.conf"
  cbox::proxy_render_config "$out" 3128
  grep -q "myproject" "$out"
  grep -q "example.com" "$out"
}

@test "cbox::proxy_render_config strips comments and whitespace" {
  cat > "${_CBOX_CONFIG_DIR_OVERRIDE}/allowlist.d/myproject.txt" <<'EOF'
# This is a comment
  .test.com
   # indented comment

.other.com  # trailing comment
EOF
  out="${CBOX_TMP}/squid.conf"
  cbox::proxy_render_config "$out" 3128
  grep -q "test.com" "$out"
  grep -q "other.com" "$out"
  ! grep -q "^# This is a comment" "$out"
}

@test "cbox::proxy_render_config emits per-acl http_access rules" {
  printf '.example.com\n' > "${_CBOX_CONFIG_DIR_OVERRIDE}/allowlist.d/myproject.txt"
  out="${CBOX_TMP}/squid.conf"
  cbox::proxy_render_config "$out" 3128
  grep -q "http_access allow CONNECT _default SSL_ports" "$out"
  grep -q "http_access allow CONNECT myproject SSL_ports" "$out"
}

@test "cbox::proxy_render_config result parses cleanly with squid -k parse" {
  out="${CBOX_TMP}/squid.conf"
  cbox::proxy_render_config "$out" 3128
  if command -v squid >/dev/null 2>&1; then
    run squid -k parse -f "$out"
    [[ "$status" -eq 0 ]] || { echo "squid output: $output"; return 1; }
  else
    skip "squid not installed"
  fi
}
