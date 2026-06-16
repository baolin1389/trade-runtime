#!/bin/bash
# trade-mcp - one-line installer.
#
# Always pulls the binary tarball from the PUBLIC runtime repo
# (baolin1389/trade-runtime). Source code lives in a private repo and
# is never distributed to clients.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash -s -- v0.4.0
#   curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash -s -- --prefix ~/.local/trade-mcp
#
# Options:
#   VERSION         Pin a specific version (defaults to whatever manifest.json
#                   points at on the runtime repo).
#   --prefix DIR    Installation root (default: /opt/trade-mcp)
#   --bin-dir DIR   Symlink directory (default: /usr/local/bin)
#   --no-symlink    Skip symlink creation
#   --no-verify     Skip sha256 verification against manifest.json
#   -h, --help      Show help

set -e

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

RUNTIME_REPO="baolin1389/trade-runtime"
RAW_BASE="https://raw.githubusercontent.com/${RUNTIME_REPO}/main"
INSTALL_DIR="/opt/trade-mcp"
BIN_DIR="/usr/local/bin"
CREATE_SYMLINK=1
VERIFY=1
VERSION=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat <<'EOF'
trade-mcp one-line installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash -s -- v0.4.0
  curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash -s -- --prefix ~/.local/trade-mcp

Options:
  VERSION         Pin a specific version (default: latest from manifest.json)
  --prefix DIR    Installation root (default: /opt/trade-mcp)
  --bin-dir DIR   Symlink directory (default: /usr/local/bin)
  --no-symlink    Skip symlink creation
  --no-verify     Skip sha256 verification against manifest.json
  -h, --help      Show help
EOF
            exit 0
            ;;
        --prefix)      INSTALL_DIR="$2"; shift 2 ;;
        --bin-dir)     BIN_DIR="$2"; shift 2 ;;
        --no-symlink)  CREATE_SYMLINK=0; shift ;;
        --no-verify)   VERIFY=0; shift ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                echo "WARNING: ignoring extra argument '$1'" >&2
            fi
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Environment check
# ---------------------------------------------------------------------------

echo "============================================"
echo "  trade-mcp installer"
echo "============================================"

if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo ""
    echo "ERROR: this prebuilt release is Linux x86_64; $OSTYPE is not supported."
    echo "Build from source or wait for a platform-specific release."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is required but not installed"
    exit 1
fi
if ! command -v tar &> /dev/null; then
    echo "ERROR: tar is required but not installed"
    exit 1
fi
if ! command -v sha256sum &> /dev/null; then
    echo "ERROR: sha256sum is required but not installed"
    exit 1
fi

# ---------------------------------------------------------------------------
# Pull manifest.json from the runtime repo. This file is the single source
# of truth for "what's the latest version" and "what's its sha256".
# ---------------------------------------------------------------------------

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

MANIFEST_URL="${RAW_BASE}/manifest.json"
echo ""
echo "→ Fetching ${MANIFEST_URL}"
if ! curl -fsSL -o "$TMP_DIR/manifest.json" "$MANIFEST_URL"; then
    echo "ERROR: failed to fetch manifest.json from $RUNTIME_REPO"
    exit 1
fi

# Tiny JSON parser that doesn't need jq.
# We support the subset of fields this script reads.
parse_json_string() {
    # $1=key, $2=file
    python3 -c "
import json, sys
data = json.load(open(r'''$2'''))
val = data
for part in r'''$1'''.split('.'):
    if part == '': continue
    val = val[part] if isinstance(val, dict) else val
print(val if val is not None else '')
"
}

if [[ -n "$VERSION" ]]; then
    echo "→ Using pinned version: $VERSION (manifest stays authoritative for sha256)"
    BARE="${VERSION#v}"
    MANIFEST_VERSION="$VERSION"
else
    MANIFEST_VERSION=$(parse_json_string version "$TMP_DIR/manifest.json")
    BARE=$(parse_json_string bare_version "$TMP_DIR/manifest.json")
    if [[ -z "$MANIFEST_VERSION" ]]; then
        echo "ERROR: manifest.json has no 'version' field"
        cat "$TMP_DIR/manifest.json"
        exit 1
    fi
fi

EXPECTED_SHA=$(parse_json_string sha256 "$TMP_DIR/manifest.json")
EXPECTED_SIZE=$(parse_json_string size_bytes "$TMP_DIR/manifest.json")
ARTIFACT_NAME=$(parse_json_string artifact "$TMP_DIR/manifest.json")
ARTIFACT_NAME="${ARTIFACT_NAME:-runtime-last.tar.gz}"

echo "  version : $MANIFEST_VERSION"
echo "  sha256  : $EXPECTED_SHA"
echo "  size    : $EXPECTED_SIZE bytes"
echo ""

# ---------------------------------------------------------------------------
# Download the artifact
# ---------------------------------------------------------------------------

# The runtime repo always exposes the latest build as runtime-last.tar.gz
# at the repo root (raw.githubusercontent.com only serves files at HEAD).
# Older versions are not retained in this minimal scheme; if you need
# historical versions, store them as GitHub release assets and add a
# /releases/download/<tag>/ path here.
DOWNLOAD_URL="${RAW_BASE}/${ARTIFACT_NAME}"
TARBALL="$TMP_DIR/$ARTIFACT_NAME"

echo "→ Downloading $DOWNLOAD_URL"
if ! curl -fsSL --retry 3 -o "$TARBALL" "$DOWNLOAD_URL"; then
    echo "ERROR: download failed"
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

if [[ "$VERIFY" -eq 1 ]]; then
    echo "→ Verifying sha256"
    ACTUAL_SHA=$(sha256sum "$TARBALL" | awk '{print $1}')
    if [[ -n "$EXPECTED_SHA" && "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
        echo "ERROR: sha256 mismatch"
        echo "  expected: $EXPECTED_SHA"
        echo "  actual  : $ACTUAL_SHA"
        exit 1
    fi
    echo "  OK ($ACTUAL_SHA)"
fi

ACTUAL_SIZE=$(stat -c %s "$TARBALL" 2>/dev/null || stat -f %z "$TARBALL")
if [[ -n "$EXPECTED_SIZE" && "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
    echo "WARNING: size mismatch (expected $EXPECTED_SIZE, got $ACTUAL_SIZE)" >&2
fi

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------

echo ""
echo "→ Extracting to $INSTALL_DIR"

EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
if ! tar -xzf "$TARBALL" -C "$EXTRACT_DIR"; then
    echo "ERROR: extract failed"
    exit 1
fi

if [[ ! -d "$EXTRACT_DIR/trade-mcp" ]]; then
    echo "ERROR: tarball does not contain a trade-mcp/ directory"
    ls -la "$EXTRACT_DIR/"
    exit 1
fi

if [[ -d "$INSTALL_DIR" ]]; then
    echo "  Removing previous installation at $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
fi
mkdir -p "$(dirname "$INSTALL_DIR")"
mv "$EXTRACT_DIR/trade-mcp" "$INSTALL_DIR"
chmod 0755 "$INSTALL_DIR/bin/trade-mcp"

# ---------------------------------------------------------------------------
# Symlink
# ---------------------------------------------------------------------------

if [[ $CREATE_SYMLINK -eq 1 ]]; then
    echo ""
    echo "→ Creating symlink at $BIN_DIR/trade-mcp"
    mkdir -p "$BIN_DIR"
    ln -sf "$INSTALL_DIR/bin/trade-mcp" "$BIN_DIR/trade-mcp"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

ACTUAL_VERSION=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "$MANIFEST_VERSION")

echo ""
echo "============================================"
echo "  Installed trade-mcp $ACTUAL_VERSION"
echo "============================================"
echo ""
echo "Install root : $INSTALL_DIR"
echo "Binary       : $INSTALL_DIR/bin/trade-mcp"
if [[ $CREATE_SYMLINK -eq 1 ]]; then
    echo "On PATH      : $BIN_DIR/trade-mcp"
fi
echo ""
echo "Configure your MCP client (Claude / OpenClaw / Hermes):"
echo ""
cat <<EOF
  {
    "mcpServers": {
      "trade-mcp": {
        "command": "$INSTALL_DIR/bin/trade-mcp",
        "args": []
      }
    }
  }
EOF
echo ""
echo "Smoke test:"
echo "  echo '{\"method\":\"tools/list\"}' | $INSTALL_DIR/bin/trade-mcp | head -c 200"
echo ""
echo "Uninstall:"
echo "  rm -rf $INSTALL_DIR"
if [[ $CREATE_SYMLINK -eq 1 ]]; then
    echo "  rm -f $BIN_DIR/trade-mcp"
fi
echo ""
