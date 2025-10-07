#!/usr/bin/env zsh

alias ht=helm_template

# =========================
# Internal helpers
# =========================

_helmtpl_require() {
  for cmd in helm kubectl fzf; do
    command -v "$cmd" >/dev/null || { echo "$cmd not found"; return 1; }
  done
}

_helmtpl_detect_base() {
  if [ -n "${HELM_APPS_BASE:-}" ] && [ -d "$HELM_APPS_BASE" ]; then
    echo "$HELM_APPS_BASE"
  elif [ -d "argocd/apps/base" ]; then
    echo "argocd/apps/base"
  elif [ -d "apps/base" ]; then
    echo "apps/base"
  else
    return 1
  fi
}

_helmtpl_overlays_from_base() { echo "${1/base/overlays}"; }

_helmtpl_list_apps() { find "$1" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort; }

_helmtpl_select() { fzf --prompt="$1"; }

_helmtpl_pick_app() {
  local base="$1" apps app
  apps="$(_helmtpl_list_apps "$base")"
  [ -n "$apps" ] || { echo "No apps in $base"; return 1; }
  app="$(echo "$apps" | _helmtpl_select "Select app: ")"
  [ -n "$app" ] || { echo "No app selected"; return 1; }
  echo "$app"
}

_helmtpl_pick_cluster() {
  local ctxs ctx
  ctxs="$(kubectl config get-contexts -o name 2>/dev/null | sort)"
  [ -n "$ctxs" ] || { echo "No kube contexts found"; return 1; }
  ctx="$(echo "$ctxs" | _helmtpl_select "Select cluster: ")"
  [ -n "$ctx" ] || { echo "No cluster selected"; return 1; }
  echo "$ctx"
}

_helmtpl_outdir() { mkdir -p "output"; echo "output"; }

_helmtpl_build_deps() {
  local chart_dir="$1"
  [ -f "$chart_dir/Chart.yaml" ] || return 0
  local cmd="${HELM_DEP_CMD:-build}" # build|update
  case "$cmd" in build|update) : ;; *) cmd="build" ;; esac
  echo "Resolving chart dependencies in: $chart_dir (helm dependency $cmd)"
  helm dependency "$cmd" "$chart_dir"
}

# Try a template render. Args: app cluster chart_path [fargs...]
_helmtpl_try_template() {
  local app="$1" cluster="$2" chart_path="$3"; shift 3
  local outdir; outdir="$(_helmtpl_outdir)"
  local outfile="$outdir/${app}-${cluster}.yaml"

  # capture stderr to show on failure
  if helm template "$app" "$chart_path" "$@" --set-string "global.cluster=$cluster" >"$outfile" 2>"/tmp/helmtpl.err"; then
    echo "Rendered: $outfile"
    return 0
  else
    # bubble up error, keep stderr available
    cat /tmp/helmtpl.err 1>&2
    rm -f /tmp/helmtpl.err
    return 1
  fi
}

# =========================
# Public entrypoint
# =========================
helm_template() {
  setopt LOCAL_OPTIONS NO_UNSET
  _helmtpl_require || return 1

  # validate repo layout early
  local base; base="$(_helmtpl_detect_base)" || {
    echo "Error: not in a valid Helm repo (need argocd/apps/base or apps/base or HELM_APPS_BASE)"; return 1; }
  local overlays; overlays="$(_helmtpl_overlays_from_base "$base")"
  [ -d "$overlays" ] || echo "Warning: overlays path not found: $overlays"

  local app="${1:-}"; local cluster="${2:-}"
  [ -n "$app" ] || app="$(_helmtpl_pick_app "$base")"
  [ -n "$cluster" ] || cluster="$(_helmtpl_pick_cluster)"

  local app_base_dir="$base/$app"
  [ -d "$app_base_dir" ] || { echo "App not found: $app_base_dir"; return 1; }
  local app_overlay_dir="$overlays/$cluster/$app"
  [ -d "$app_overlay_dir" ] || echo "Warning: overlay not found: $app_overlay_dir"

  # -f args as array (zsh-safe)
  local -a fargs=()
  [ -f "$app_base_dir/values.yaml" ]    && fargs+=(-f "$app_base_dir/values.yaml")
  [ -f "$app_overlay_dir/values.yaml" ] && fargs+=(-f "$app_overlay_dir/values.yaml")

  # 1) try render
  if _helmtpl_try_template "$app" "$cluster" "$app_base_dir" "${fargs[@]}"; then
    return 0
  fi

  # 2) on failure, resolve deps then retry once
  echo "Initial render failed. Attempting dependency resolution..."
  _helmtpl_build_deps "$app_base_dir" || { echo "Dependency resolution failed"; return 1; }

  _helmtpl_try_template "$app" "$cluster" "$app_base_dir" "${fargs[@]}"
}