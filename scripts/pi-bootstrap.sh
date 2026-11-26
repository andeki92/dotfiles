#!/usr/bin/env bash
# Idempotent bootstrap script for Pi + team package + Gondolin sandbox +
# herdr & Atuin integrations.
#
# Safe to re-run any number of times by any WSL/Linux/macOS user.
# Uses no hardcoded usernames or machine-specific absolute paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
BIN_DIR="${PI_BIN_DIR:-$HOME/.local/bin}"

# Ensure ~/.local/bin is on PATH during bootstrap
export PATH="$BIN_DIR:$PATH"

log()  { printf '[pi-bootstrap] %s\n' "$*"; }
warn() { printf '[pi-bootstrap] WARN: %s\n' "$*" >&2; }
die()  { printf '[pi-bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

# 1. Check core prerequisites
for cmd in node npm curl; do
  command -v "$cmd" >/dev/null 2>&1 || die "Required command missing: $cmd"
done

if ! node -e 'const [maj,min] = process.versions.node.split(".").map(Number); process.exit(maj > 22 || (maj === 22 && min >= 19) ? 0 : 1)'; then
  die "Pi and Gondolin require Node.js >= 22.19.0 (found $(node --version))"
fi

# 2. Stow the `pi` dotfiles module (~/.config/sandbox.toml, ~/.local/bin/*, ~/.local/share/pi-team-package)
if command -v stow >/dev/null 2>&1 && [[ -d "$DOTFILES_ROOT/config/pi" ]]; then
  log "Stowing config/pi into $HOME..."
  mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}" "$BIN_DIR" "$XDG_DATA"
  (cd "$DOTFILES_ROOT" && stow -R pi)
else
  warn "stow not found or config/pi missing; assuming team package is already at $XDG_DATA/pi-team-package"
fi

TEAM_PKG_DIR="${PI_TEAM_PACKAGE_DIR:-$XDG_DATA/pi-team-package}"
[[ -f "$TEAM_PKG_DIR/package.json" ]] || die "Team Pi package not found at $TEAM_PKG_DIR"
[[ -f "$TEAM_PKG_DIR/pi-pin.json" ]] || die "Pin file not found at $TEAM_PKG_DIR/pi-pin.json"

SELF_UPDATE_BIN="$BIN_DIR/pi-self-update"
[[ -x "$SELF_UPDATE_BIN" ]] || SELF_UPDATE_BIN="$DOTFILES_ROOT/config/pi/.local/bin/pi-self-update"

# 3. Install/sync pinned Pi version via official installer release lockfiles
log "Syncing pinned Pi binary..."
"$SELF_UPDATE_BIN" --sync --pin-file "$TEAM_PKG_DIR/pi-pin.json"

# 4. Install runtime dependencies for the local team package (Gondolin + optional krun runner)
log "Installing team package dependencies (npm ci --ignore-scripts --include=optional)..."
(
  cd "$TEAM_PKG_DIR"
  if [[ -f package-lock.json ]]; then
    npm ci --ignore-scripts --include=optional --no-fund --no-audit --loglevel=error --progress=false
  else
    npm install --ignore-scripts --include=optional --no-fund --no-audit --loglevel=error --progress=false
  fi
)

# 5. Initialize ~/.pi/agent as a REAL directory (never a Stow symlink so auth.json/sessions stay local)
mkdir -p "$AGENT_DIR/extensions/subagent"

# Link global AGENTS.md from team package template (only overwrite if missing or already a symlink)
AGENTS_DEST="$AGENT_DIR/AGENTS.md"
AGENTS_SRC="$TEAM_PKG_DIR/templates/AGENTS.md"
if [[ ! -e "$AGENTS_DEST" || -L "$AGENTS_DEST" ]]; then
  ln -sfn "$AGENTS_SRC" "$AGENTS_DEST"
  log "Linked $AGENTS_DEST -> $AGENTS_SRC"
else
  warn "$AGENTS_DEST exists as a regular file; leaving untouched (template is at $AGENTS_SRC)"
fi

# Merge settings.template.json into ~/.pi/agent/settings.json idempotently without
# clobbering personal settings (defaultModel, theme, etc.).
SETTINGS_DEST="$AGENT_DIR/settings.json"
SETTINGS_TEMPLATE="$TEAM_PKG_DIR/templates/settings.template.json"
node - "$SETTINGS_DEST" "$SETTINGS_TEMPLATE" "$TEAM_PKG_DIR/pi-pin.json" <<'NODE'
const fs = require("node:fs");
const [destPath, tplPath, pinPath] = process.argv.slice(2);
const template = JSON.parse(fs.readFileSync(tplPath, "utf8"));
const pin = JSON.parse(fs.readFileSync(pinPath, "utf8"));

let existing = {};
if (fs.existsSync(destPath)) {
  existing = JSON.parse(fs.readFileSync(destPath, "utf8"));
}

// Preserve personal settings while enforcing baseline security/update controls.
const existingTools = Array.isArray(existing.defaultTools) ? existing.defaultTools : null;
let defaultTools;
if (!existingTools) {
  defaultTools = [...template.defaultTools];
} else if (existingTools.some((t) => t === "codemode" || t === "+codemode" || t === "-codemode")) {
  defaultTools = existingTools;
} else {
  defaultTools = [...existingTools, "+codemode"];
}

const merged = {
  $schema: template.$schema,
  ...existing,
  defaultProjectTrust: template.defaultProjectTrust,
  defaultTools,
  codemode: {
    ...template.codemode,
    ...(existing.codemode && typeof existing.codemode === "object" ? existing.codemode : {}),
  },
  enableInstallTelemetry: template.enableInstallTelemetry,
  enableAnalytics: template.enableAnalytics,
  selfUpdateCommand: template.selfUpdateCommand,
};

// Reconcile pinned package list: keep any extra user packages, update/add pinned specs.
const desiredPackages = [
  "~/.local/share/pi-team-package",
  ...(Array.isArray(pin.thirdPartyPackages) ? pin.thirdPartyPackages : []),
];

const pkgIdentity = (entry) => {
  const src = typeof entry === "string" ? entry : entry?.source;
  if (typeof src !== "string") return "";
  if (src.startsWith("npm:")) {
    const rest = src.slice(4);
    const idx = rest.lastIndexOf("@");
    return idx > 0 ? `npm:${rest.slice(0, idx)}` : `npm:${rest}`;
  }
  if (src.startsWith("git:")) {
    const idx = src.lastIndexOf("@");
    return idx > 4 ? src.slice(0, idx) : src;
  }
  return src;
};

const existingList = Array.isArray(existing.packages) ? existing.packages : [];
const desiredById = new Map(desiredPackages.map((p) => [pkgIdentity(p), p]));
const nextPackages = [];
const seen = new Set();

for (const item of desiredPackages) {
  const id = pkgIdentity(item);
  nextPackages.push(item);
  seen.add(id);
}
for (const item of existingList) {
  const id = pkgIdentity(item);
  if (id && !seen.has(id) && !desiredById.has(id)) {
    nextPackages.push(item);
    seen.add(id);
  }
}

merged.packages = nextPackages;
fs.writeFileSync(destPath, `${JSON.stringify(merged, null, 2)}\n`, { mode: 0o600 });
NODE
log "Reconciled $SETTINGS_DEST"

# Ensure pi-subagents enforces background (async) execution so child subagents
# load Gondolin instead of bypassing it in-process.
SUBAGENT_CFG_DEST="$AGENT_DIR/extensions/subagent/config.json"
SUBAGENT_CFG_TPL="$TEAM_PKG_DIR/templates/subagents.config.json"
node - "$SUBAGENT_CFG_DEST" "$SUBAGENT_CFG_TPL" <<'NODE'
const fs = require("node:fs");
const [destPath, tplPath] = process.argv.slice(2);
const tpl = JSON.parse(fs.readFileSync(tplPath, "utf8"));
let existing = {};
if (fs.existsSync(destPath)) {
  existing = JSON.parse(fs.readFileSync(destPath, "utf8"));
}
const merged = {
  ...existing,
  forceTopLevelAsync: true,
  asyncByDefault: true,
};
fs.writeFileSync(destPath, `${JSON.stringify(merged, null, 2)}\n`, { mode: 0o600 });
NODE
log "Reconciled $SUBAGENT_CFG_DEST (forceTopLevelAsync=true)"

# 6. Install / reconcile pinned Pi third-party packages
# Note: `pi update --extensions` intentionally does not touch pinned npm@x.y.z specs,
# so we ensure each pinned package is installed at its exact version via `pi install`.
log "Ensuring pinned third-party Pi packages are installed..."
while IFS= read -r pkg_spec; do
  [[ -n "$pkg_spec" ]] || continue
  pkg_name=""
  pkg_ver=""
  if [[ "$pkg_spec" == npm:* ]]; then
    rest="${pkg_spec#npm:}"
    pkg_name="${rest%@*}"
    pkg_ver="${rest##*@}"
  fi
  installed_ver=""
  if [[ -n "$pkg_name" && -f "$AGENT_DIR/npm/node_modules/$pkg_name/package.json" ]]; then
    installed_ver="$(node -e '
      const fs = require("node:fs");
      const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      process.stdout.write(typeof p.version === "string" ? p.version : "");
    ' "$AGENT_DIR/npm/node_modules/$pkg_name/package.json")"
  fi
  if [[ -n "$pkg_ver" && "$installed_ver" == "$pkg_ver" ]]; then
    log "  ✓ $pkg_spec already installed"
  else
    log "  Installing $pkg_spec..."
    pi install "$pkg_spec"
  fi
done < <(node -e '
  const fs = require("node:fs");
  const pin = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  for (const p of pin.thirdPartyPackages || []) console.log(p);
' "$TEAM_PKG_DIR/pi-pin.json")

# 7. Install herdr Pi integration (if herdr is installed)
if command -v herdr >/dev/null 2>&1; then
  log "Installing herdr Pi integration..."
  herdr integration install pi
else
  warn "herdr not found on PATH; skipping 'herdr integration install pi'"
fi

# 8. Install Atuin Pi agent-history hook in local-only mode (if atuin is installed)
if command -v atuin >/dev/null 2>&1; then
  log "Installing Atuin Pi agent-history hook (sync & Threads disabled)..."
  ATUIN_CFG_DIR="${ATUIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/atuin}"
  if atuin setup --help 2>&1 | grep -q -- '--agent-history'; then
    ATUIN_CONFIG_DIR="$ATUIN_CFG_DIR" atuin setup --only --agent-history --agents pi --no-threads --no-daemon --no-mcp --sync off
  elif atuin hook --help 2>&1 | grep -q 'install'; then
    ATUIN_CONFIG_DIR="$ATUIN_CFG_DIR" atuin hook install pi
  else
    warn "Unrecognized atuin CLI version; skipping Pi hook install"
  fi
else
  warn "atuin not found on PATH; skipping Atuin Pi hook install (install via dotfiles mise/brew first)"
fi

# 9. Build custom Gondolin guest image (pi-sandbox:latest with git, gh, kustomize) if build tools exist
if [[ -x "$SCRIPT_DIR/pi-build-image.sh" ]]; then
  if command -v cpio >/dev/null 2>&1 && command -v lz4 >/dev/null 2>&1 && \
     { command -v mke2fs >/dev/null 2>&1 || command -v mkfs.ext4 >/dev/null 2>&1 || [[ -x /usr/sbin/mke2fs ]]; }; then
    log "Ensuring custom Gondolin image (pi-sandbox:latest with git, gh, kustomize) is built..."
    "$SCRIPT_DIR/pi-build-image.sh"
  else
    warn "Skipping custom Gondolin image build (install cpio, lz4, e2fsprogs then run ./scripts/pi-build-image.sh for git + gh inside KVM)."
  fi
fi

# 10. Preflight KVM virtualization check (informational; pi itself fails closed if missing)
if [[ "$(uname -s)" == "Linux" ]]; then
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    log "KVM check: /dev/kvm is readable and writable (Gondolin krun ready)."
  else
    warn "/dev/kvm is not readable/writable for $(id -un). Gondolin will refuse to start until fixed:"
    warn "  sudo usermod -aG kvm \"\$USER\"   # then start a fresh WSL/shell login"
  fi
fi

log "Bootstrap complete. Installed Pi $(pi --version)."
log "Run ./scripts/pi-sandbox-verify.sh to verify sandbox isolation and usage logging."
