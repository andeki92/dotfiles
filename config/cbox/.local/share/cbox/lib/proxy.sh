# cbox proxy — Squid lifecycle + config rendering.
# Sourced by bin/cbox alongside common.sh and state.sh.
#
# Renders ~/.config/cbox/squid.conf.template + every ~/.config/cbox/allowlist.d/*.txt
# into a single squid.conf under cbox::state_dir, then manages the daemon.
#
# Each *.txt file becomes one `acl <sanitized-filename> dstdomain <hosts...>` rule
# plus a corresponding `http_access allow CONNECT <name> SSL_ports` line.
#
# Override config dir for tests via _CBOX_CONFIG_DIR_OVERRIDE.

# ---- Path helpers --------------------------------------------------------------

cbox::_proxy_config_dir() {
  printf '%s\n' "${_CBOX_CONFIG_DIR_OVERRIDE:-$(cbox::config_dir)}"
}
cbox::_proxy_template()  { printf '%s\n' "$(cbox::_proxy_config_dir)/squid.conf.template"; }
cbox::_proxy_allow_dir() { printf '%s\n' "$(cbox::_proxy_config_dir)/allowlist.d"; }
cbox::_proxy_pid_file()  { printf '%s\n' "$(cbox::state_dir)/squid.pid"; }
cbox::_proxy_log_file()  { printf '%s\n' "$(cbox::state_dir)/squid.log"; }
cbox::_proxy_conf_file() { printf '%s\n' "$(cbox::state_dir)/squid.conf"; }

# Sanitise a filename stem to a valid Squid ACL name: [a-zA-Z0-9_]+.
cbox::_proxy_sanitize_name() {
  local raw="${1:?cbox::_proxy_sanitize_name requires a name}"
  printf '%s' "$raw" | sed 's/[^a-zA-Z0-9_]/_/g'
}

# ---- Config rendering ----------------------------------------------------------

# cbox::proxy_render_config <output_path> <port>
#
# Reads the template + every allowlist.d/*.txt and writes a complete squid.conf.
# Exits non-zero if the template is missing or no allow-list entries were found.
cbox::proxy_render_config() {
  local out="${1:?cbox::proxy_render_config requires an output path}"
  local port="${2:?cbox::proxy_render_config requires a port}"
  local tpl allow_dir
  tpl=$(cbox::_proxy_template)
  allow_dir=$(cbox::_proxy_allow_dir)

  if [[ ! -f "$tpl" ]]; then
    cbox::log_err "squid template not found: ${tpl}"
    return 1
  fi

  local pid_file log_file
  pid_file=$(cbox::_proxy_pid_file)
  log_file=$(cbox::_proxy_log_file)

  # Build per-acl blocks. Two parallel arrays: acl rules and http_access lines.
  local -a acl_lines=()
  local -a access_lines=()
  local total_hosts=0
  local file
  shopt -s nullglob
  for file in "$allow_dir"/*.txt; do
    local stem name hosts=()
    stem=$(basename "$file" .txt)
    name=$(cbox::_proxy_sanitize_name "$stem")

    # Strip comments (anything from `#` onwards) and trim whitespace.
    local line stripped
    while IFS= read -r line || [[ -n "$line" ]]; do
      stripped="${line%%#*}"
      # Trim leading + trailing whitespace.
      stripped="${stripped#"${stripped%%[![:space:]]*}"}"
      stripped="${stripped%"${stripped##*[![:space:]]}"}"
      [[ -z "$stripped" ]] && continue
      hosts+=("$stripped")
    done < "$file"

    if (( ${#hosts[@]} > 0 )); then
      acl_lines+=("acl ${name} dstdomain ${hosts[*]}")
      access_lines+=("http_access allow CONNECT ${name} SSL_ports")
      total_hosts=$((total_hosts + ${#hosts[@]}))
    fi
  done
  shopt -u nullglob

  if (( total_hosts == 0 )); then
    cbox::log_err "no allow-list entries found under ${allow_dir}"
    return 1
  fi

  # Walk the template line by line, substituting placeholders. We do this in
  # bash (not sed) so the multi-line %%ACL_DOMAINS%% block is trivial.
  #
  # %%ACL_DOMAINS%% is only honoured when it is the entire line content (after
  # trimming) — otherwise it would also match the comment header that documents
  # the placeholder, and we'd emit the ACL block twice. Other placeholders are
  # straight string substitutions safely usable inline.
  : > "$out"
  local tline trimmed rendered
  while IFS= read -r tline || [[ -n "$tline" ]]; do
    trimmed="${tline#"${tline%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ "$trimmed" == "%%ACL_DOMAINS%%" ]]; then
      local acl
      for acl in "${acl_lines[@]}"; do
        printf '%s\n' "$acl" >> "$out"
      done
    else
      rendered="${tline//%%PORT%%/$port}"
      rendered="${rendered//%%PIDFILE%%/$pid_file}"
      rendered="${rendered//%%LOGFILE%%/$log_file}"
      printf '%s\n' "$rendered" >> "$out"
    fi
  done < "$tpl"

  # Append per-acl http_access rules after the template body. Squid evaluates
  # http_access rules top-to-bottom; the template's `deny CONNECT !SSL_ports`
  # / `deny !Safe_ports` come first, then these allows, then the final
  # `deny all`. So an unmatched ACL falls through to the final deny.
  {
    printf '\n# Per-acl http_access rules (appended by proxy.sh).\n'
    local rule
    for rule in "${access_lines[@]}"; do
      printf '%s\n' "$rule"
    done
  } >> "$out"
}

# ---- Lifecycle -----------------------------------------------------------------

# Read the PID from the pid file if it exists and the process is alive. Echoes
# the pid on stdout and returns 0 if alive; returns non-zero otherwise.
cbox::_proxy_alive_pid() {
  local pid_file pid
  pid_file=$(cbox::_proxy_pid_file)
  [[ -f "$pid_file" ]] || return 1
  pid=$(<"$pid_file")
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  printf '%s\n' "$pid"
}

# cbox::proxy_ensure
#
# Idempotent. If Squid is already running, returns 0. Otherwise renders the
# config and starts squid (daemonized, default mode for `squid -f`).
cbox::proxy_ensure() {
  cbox::require_cmd squid || return 1
  if cbox::_proxy_alive_pid >/dev/null; then
    return 0
  fi

  local conf
  conf=$(cbox::_proxy_conf_file)
  mkdir -p "$(dirname "$conf")"
  if ! cbox::proxy_render_config "$conf" 3128; then
    return 1
  fi

  # squid 7.x daemonizes by default; -N would force foreground. We want
  # daemonized so the pid file is written and we can return.
  if ! squid -f "$conf"; then
    cbox::log_err "squid failed to start (see $(cbox::_proxy_log_file))"
    return 1
  fi

  # Wait briefly for the pid file to materialize.
  local pid_file waited
  pid_file=$(cbox::_proxy_pid_file)
  waited=0
  while (( waited < 50 )); do
    if [[ -f "$pid_file" ]] && cbox::_proxy_alive_pid >/dev/null; then
      cbox::log_ok "squid started (pid $(<"$pid_file"))"
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done

  cbox::log_err "squid pid file did not appear within 5s (check $(cbox::_proxy_log_file))"
  return 1
}

# cbox::proxy_reload
#
# Regenerate config and tell Squid to reload. No-op if Squid isn't running.
cbox::proxy_reload() {
  if ! cbox::_proxy_alive_pid >/dev/null; then
    cbox::log_warn "squid is not running; nothing to reload"
    return 0
  fi
  local conf
  conf=$(cbox::_proxy_conf_file)
  cbox::proxy_render_config "$conf" 3128 || return 1
  if ! squid -k reconfigure -f "$conf"; then
    cbox::log_err "squid reconfigure failed"
    return 1
  fi
  cbox::log_ok "squid reloaded"
}

# cbox::proxy_stop_if_idle
#
# If state_list reports zero sessions, stop squid. Tries graceful shutdown
# first, then SIGTERM as a fallback.
cbox::proxy_stop_if_idle() {
  local count
  if ! count=$(cbox::state_list 2>/dev/null | jq -r 'length' 2>/dev/null); then
    count=0
  fi
  if [[ "${count:-0}" -gt 0 ]]; then
    return 0
  fi

  local pid
  pid=$(cbox::_proxy_alive_pid) || return 0   # not running, nothing to do

  local conf pid_file waited
  conf=$(cbox::_proxy_conf_file)
  pid_file=$(cbox::_proxy_pid_file)

  if [[ -f "$conf" ]]; then
    squid -k shutdown -f "$conf" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  else
    kill -TERM "$pid" 2>/dev/null || true
  fi

  waited=0
  while (( waited < 50 )); do
    if [[ ! -f "$pid_file" ]] || ! cbox::_proxy_alive_pid >/dev/null; then
      cbox::log_ok "squid stopped"
      rm -f "$pid_file"
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done

  cbox::log_warn "squid did not exit within 5s; sending SIGKILL"
  kill -KILL "$pid" 2>/dev/null || true
  rm -f "$pid_file"
}

# cbox::proxy_status
#
# Print a one-line human-readable status. Exit 0 if running, non-zero if not.
cbox::proxy_status() {
  local pid
  if pid=$(cbox::_proxy_alive_pid); then
    printf 'squid: running (pid %s, conf %s)\n' "$pid" "$(cbox::_proxy_conf_file)"
    return 0
  fi
  printf 'squid: not running\n'
  return 1
}
