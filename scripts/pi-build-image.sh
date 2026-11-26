#!/usr/bin/env bash
# Build and tag the Gondolin guest image (`pi-sandbox:latest`) containing
# git, gh (GitHub CLI), kustomize, ripgrep, jq, node, python3, and uv, plus
# pre-baked /etc/gitconfig (gh HTTPS credential helper) and /workspace mount point.
#
# Safe to re-run; pass --force to rebuild even when pi-sandbox:latest already exists.

set -euo pipefail

XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
TEAM_PKG_DIR="${PI_TEAM_PACKAGE_DIR:-$XDG_DATA/pi-team-package}"
IMAGE_TAG="${PI_SANDBOX_IMAGE:-pi-sandbox:latest}"
BUILD_CFG="$TEAM_PKG_DIR/gondolin-image/build-config.json"
GONDOLIN_BIN="$TEAM_PKG_DIR/node_modules/.bin/gondolin"

FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --tag)   IMAGE_TAG="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: pi-build-image.sh [--force] [--tag REF]

Builds and tags the Gondolin guest image (default: pi-sandbox:latest)
with git, gh (github-cli), kustomize, ripgrep, jq, node, python3, and uv.
EOF
      exit 0
      ;;
    *)
      printf '[pi-build-image] Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

log()  { printf '[pi-build-image] %s\n' "$*"; }
die()  { printf '[pi-build-image] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$BUILD_CFG" ]] || die "Build config not found: $BUILD_CFG (run ./scripts/pi-bootstrap.sh first)"
[[ -x "$GONDOLIN_BIN" ]] || die "Gondolin CLI not found at $GONDOLIN_BIN (run ./scripts/pi-bootstrap.sh first)"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64|amd64)   TARGET_ARCH="x86_64" ;;
  aarch64|arm64)  TARGET_ARCH="aarch64" ;;
  *)              die "Unsupported host architecture: $HOST_ARCH" ;;
esac

if [[ "$FORCE" -eq 0 ]]; then
  if "$GONDOLIN_BIN" image ls 2>/dev/null | awk '{print $1}' | grep -Fxq "$IMAGE_TAG"; then
    log "Image $IMAGE_TAG already exists in local Gondolin store (pass --force to rebuild)."
    exit 0
  fi
fi

# Ensure mke2fs, cpio, and lz4 are discoverable (including Homebrew keg-only e2fsprogs on macOS/Linux)
if command -v brew >/dev/null 2>&1; then
  E2FS_PREFIX="$(brew --prefix e2fsprogs 2>/dev/null || true)"
  if [[ -n "$E2FS_PREFIX" && -d "$E2FS_PREFIX/sbin" ]]; then
    export PATH="$E2FS_PREFIX/sbin:$E2FS_PREFIX/bin:$PATH"
  fi
fi
export PATH="/usr/sbin:/sbin:$PATH"

missing=()
command -v cpio >/dev/null 2>&1 || missing+=("cpio")
command -v lz4 >/dev/null 2>&1 || missing+=("lz4")
if ! command -v mke2fs >/dev/null 2>&1 && ! command -v mkfs.ext4 >/dev/null 2>&1; then
  missing+=("e2fsprogs (mke2fs)")
fi
if [[ ${#missing[@]} -gt 0 ]]; then
  die "Missing image-build prerequisites: ${missing[*]}. Install via: sudo apt install cpio lz4 e2fsprogs (or brew install cpio lz4 e2fsprogs)."
fi

log "Building Gondolin image $IMAGE_TAG for $TARGET_ARCH from $BUILD_CFG..."
BUILD_OUT="$(mktemp -d "${TMPDIR:-/tmp}/gondolin-pi-sandbox.XXXXXX")"
trap 'rm -rf "$BUILD_OUT"' EXIT

"$GONDOLIN_BIN" build --config "$BUILD_CFG" --arch "$TARGET_ARCH" --output "$BUILD_OUT"

# Workaround for @earendil-works/gondolin@0.14.0 on x86_64:
# Local `gondolin build` extracts the raw libkrunfw payload without the 4096-byte
# ELF64 wrapper header expected by libkrun (causing "Kernel doesn't fit in RAM").
# If krun-kernel is not yet an ELF executable on x86_64, wrap it cleanly and
# update manifest.json's checksum + buildId before verifying and importing.
if [[ "$TARGET_ARCH" == "x86_64" && -f "$BUILD_OUT/krun-kernel" ]]; then
  node - "$BUILD_OUT" <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const outDir = process.argv[2];
const kernelPath = path.join(outDir, "krun-kernel");
const raw = fs.readFileSync(kernelPath);

// Already an ELF binary (e.g., newer Gondolin release) — nothing to do.
if (raw.length >= 4 && raw[0] === 0x7f && raw[1] === 0x45 && raw[2] === 0x4c && raw[3] === 0x46) {
  process.exit(0);
}

const LOAD_ADDR = 0x1000000n;
const ENTRY_ADDR = 0x1000123n;
const HEADER_SIZE = 4096;
const hdr = Buffer.alloc(HEADER_SIZE, 0);

// ELF64 header (64 bytes)
hdr.set([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0], 0); // EI_MAG, ELFCLASS64, ELFDATA2LSB, EV_CURRENT
hdr.writeUInt16LE(2, 16);            // e_type = ET_EXEC
hdr.writeUInt16LE(62, 18);           // e_machine = EM_X86_64
hdr.writeUInt32LE(1, 20);            // e_version = EV_CURRENT
hdr.writeBigUInt64LE(ENTRY_ADDR, 24);// e_entry
hdr.writeBigUInt64LE(64n, 32);       // e_phoff
hdr.writeBigUInt64LE(0n, 40);        // e_shoff
hdr.writeUInt32LE(0, 48);            // e_flags
hdr.writeUInt16LE(64, 52);           // e_ehsize
hdr.writeUInt16LE(56, 54);           // e_phentsize
hdr.writeUInt16LE(1, 56);            // e_phnum
hdr.writeUInt16LE(64, 58);           // e_shentsize
hdr.writeUInt16LE(0, 60);            // e_shnum
hdr.writeUInt16LE(0, 62);            // e_shstrndx

// Single PT_LOAD program header (56 bytes at offset 64)
const ph = 64;
const size = BigInt(raw.length);
hdr.writeUInt32LE(1, ph + 0);        // p_type = PT_LOAD
hdr.writeUInt32LE(7, ph + 4);        // p_flags = PF_R | PF_W | PF_X
hdr.writeBigUInt64LE(BigInt(HEADER_SIZE), ph + 8); // p_offset = 0x1000
hdr.writeBigUInt64LE(LOAD_ADDR, ph + 16);          // p_vaddr
hdr.writeBigUInt64LE(LOAD_ADDR, ph + 24);          // p_paddr
hdr.writeBigUInt64LE(size, ph + 32);               // p_filesz
hdr.writeBigUInt64LE(size, ph + 40);               // p_memsz
hdr.writeBigUInt64LE(0x1000n, ph + 48);            // p_align

const wrapped = Buffer.concat([hdr, raw]);
fs.writeFileSync(kernelPath, wrapped);

const sha = crypto.createHash("sha256").update(wrapped).digest("hex");
const manifestPath = path.join(outDir, "manifest.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
manifest.checksums = { ...(manifest.checksums || {}), krunKernel: sha };
// Recompute deterministic UUIDv5-style buildId from checksums so store import gets a clean unique ID.
const idHash = crypto
  .createHash("sha256")
  .update(JSON.stringify(manifest.checksums))
  .digest("hex");
manifest.buildId = [
  idHash.slice(0, 8),
  idHash.slice(8, 12),
  `4${idHash.slice(13, 16)}`,
  `a${idHash.slice(17, 20)}`,
  idHash.slice(20, 32),
].join("-");
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`[pi-build-image] Wrapped x86_64 krun-kernel with ELF64 header (sha256=${sha.slice(0, 12)}...)`);
NODE
fi

"$GONDOLIN_BIN" build --verify "$BUILD_OUT"
"$GONDOLIN_BIN" image import "$BUILD_OUT" --tag "$IMAGE_TAG"
"$GONDOLIN_BIN" image rm --untagged --yes >/dev/null 2>&1 || true

log "Built and tagged $IMAGE_TAG:"
"$GONDOLIN_BIN" image inspect "$IMAGE_TAG" --arch "$TARGET_ARCH"
