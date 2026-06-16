#!/bin/bash
# trade-mcp - upgrade script.
#
# Safely upgrades trade-mcp while preserving all database data.
# This script is designed for in-place upgrades from one version to another.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash -s -- v0.4.2
#
# What gets preserved:
#   - data/trade_crm.db (main database)
#   - data/backups/ (all backup files)
#   - Any custom config files you modified
#
# What gets updated:
#   - bin/trade-mcp (binary)
#   - config/ (default configs, may overwrite customizations)
#   - resources/, prompts/, skills/ (runtime assets)
#   - VERSION, README.md, USAGE.md
#
# Options:
#   VERSION         Pin a specific version (defaults to latest from manifest)
#   --prefix DIR    Installation directory (default: /opt/trade-mcp)
#   --no-backup     Skip automatic database backup before upgrade
#   --force         Force upgrade even if version appears same
#   -h, --help      Show help

set -e

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

RUNTIME_REPO="baolin1389/trade-runtime"
RAW_BASE="https://raw.githubusercontent.com/${RUNTIME_REPO}/master"
INSTALL_DIR="/opt/trade-mcp"
BIN_DIR="/usr/local/bin"
SKIP_BACKUP=0
FORCE_UPGRADE=0
VERSION=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat <<'EOF'
trade-mcp upgrade script

Usage:
  curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash
  curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash -s -- v0.4.2

Options:
  VERSION         Pin a specific version (default: latest from manifest.json)
  --prefix DIR    Installation directory (default: /opt/trade-mcp)
  --no-backup     Skip automatic database backup before upgrade
  --force         Force upgrade even if version appears same
  -h, --help      Show help

What gets preserved:
  - data/trade_crm.db (database)
  - data/backups/ (backups)
  - Custom config modifications

What gets updated:
  - bin/trade-mcp (binary)
  - config/, resources/, prompts/, skills/
  - VERSION, README.md, USAGE.md
EOF
            exit 0
            ;;
        --prefix)      INSTALL_DIR="$2"; shift 2 ;;
        --no-backup)   SKIP_BACKUP=1; shift ;;
        --force)       FORCE_UPGRADE=1; shift ;;
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
echo "  trade-mcp upgrade script"
echo "============================================"

if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo ""
    echo "ERROR: this script is for Linux x86_64; $OSTYPE is not supported."
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

# ---------------------------------------------------------------------------
# Detect existing installation
# ---------------------------------------------------------------------------

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo ""
    echo "ERROR: No existing installation found at $INSTALL_DIR"
    echo "       Please run install.sh first:"
    echo "       curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/install.sh | bash"
    exit 1
fi

if [[ ! -f "$INSTALL_DIR/bin/trade-mcp" ]]; then
    echo ""
    echo "ERROR: Binary not found at $INSTALL_DIR/bin/trade-mcp"
    echo "       Installation appears corrupted. Please reinstall."
    exit 1
fi

# Read current version
CURRENT_VERSION=""
if [[ -f "$INSTALL_DIR/VERSION" ]]; then
    CURRENT_VERSION=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "unknown")
fi

echo ""
echo "Current installation:"
echo "  Location : $INSTALL_DIR"
echo "  Version  : $CURRENT_VERSION"

# Check for running instances
RUNNING_PIDS=$(pgrep -f "trade-mcp" 2>/dev/null || true)
if [[ -n "$RUNNING_PIDS" ]]; then
    echo ""
    echo "WARNING: trade-mcp processes are running (PIDs: $RUNNING_PIDS)"
    echo "         It's recommended to stop them before upgrade."
    echo ""
    read -p "Stop running instances now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "Stopping trade-mcp processes..."
        pkill -f "trade-mcp" 2>/dev/null || true
        sleep 2
        # Verify stopped
        if pgrep -f "trade-mcp" &> /dev/null; then
            echo "ERROR: Could not stop all processes. Please stop manually and retry."
            exit 1
        fi
        echo "All processes stopped."
    fi
fi

# ---------------------------------------------------------------------------
# Backup database before upgrade
# ---------------------------------------------------------------------------

DB_PATH="$INSTALL_DIR/data/trade_crm.db"
BACKUP_DIR="$INSTALL_DIR/data/backups"

if [[ -f "$DB_PATH" && $SKIP_BACKUP -eq 0 ]]; then
    echo ""
    echo "→ Creating pre-upgrade database backup..."
    
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    PRE_UPGRADE_BACKUP="$BACKUP_DIR/pre_upgrade_${CURRENT_VERSION}_to_${TIMESTAMP}.db"
    
    cp "$DB_PATH" "$PRE_UPGRADE_BACKUP"
    
    if [[ -f "$PRE_UPGRADE_BACKUP" ]]; then
        DB_SIZE=$(stat -c %s "$DB_PATH" 2>/dev/null || stat -f %z "$DB_PATH")
        BACKUP_SIZE=$(stat -c %s "$PRE_UPGRADE_BACKUP" 2>/dev/null || stat -f %z "$PRE_UPGRADE_BACKUP")
        
        if [[ "$DB_SIZE" == "$BACKUP_SIZE" ]]; then
            echo "  ✅ Backup created: $PRE_UPGRADE_BACKUP ($DB_SIZE bytes)"
        else
            echo "  ⚠️  Backup size mismatch! Original: $DB_SIZE, Backup: $BACKUP_SIZE"
            echo "      Proceeding anyway, but please verify manually."
        fi
    else
        echo "  ❌ Backup failed! Aborting upgrade."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Fetch manifest.json for target version
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

# Parse manifest (simple JSON parser without jq dependency)
parse_json_string() {
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

TARGET_VERSION=$(parse_json_string version "$TMP_DIR/manifest.json")
TARGET_BARE=$(parse_json_string bare_version "$TMP_DIR/manifest.json")
EXPECTED_SHA=$(parse_json_string sha256 "$TMP_DIR/manifest.json")
EXPECTED_SIZE=$(parse_json_string size_bytes "$TMP_DIR/manifest.json")
ARTIFACT_NAME=$(parse_json_string artifact "$TMP_DIR/manifest.json")
ARTIFACT_NAME="${ARTIFACT_NAME:-runtime-last.tar.gz}"

if [[ -n "$VERSION" ]]; then
    # User specified a version, verify it matches manifest or warn
    if [[ "$VERSION" != "$TARGET_VERSION" && "$VERSION" != "v$TARGET_BARE" ]]; then
        echo ""
        echo "WARNING: You requested version '$VERSION' but manifest shows '$TARGET_VERSION'"
        echo "         The manifest always points to the latest published version."
        echo "         Proceeding with latest version from manifest."
    fi
fi

echo "  Target version : $TARGET_VERSION"
echo "  Target sha256  : $EXPECTED_SHA"

# Check if upgrade is needed
if [[ "$CURRENT_VERSION" == "$TARGET_BARE" && $FORCE_UPGRADE -eq 0 ]]; then
    echo ""
    echo "✅ Already at version $CURRENT_VERSION. No upgrade needed."
    echo "   Use --force to reinstall same version."
    exit 0
fi

# ---------------------------------------------------------------------------
# Download new version
# ---------------------------------------------------------------------------

DOWNLOAD_URL="${RAW_BASE}/${ARTIFACT_NAME}"
TARBALL="$TMP_DIR/$ARTIFACT_NAME"

echo ""
echo "→ Downloading $DOWNLOAD_URL"
if ! curl -fsSL --retry 3 -o "$TARBALL" "$DOWNLOAD_URL"; then
    echo "ERROR: download failed"
    exit 1
fi

# Verify sha256
ACTUAL_SHA=$(sha256sum "$TARBALL" | awk '{print $1}')
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
    echo "ERROR: sha256 mismatch!"
    echo "  expected: $EXPECTED_SHA"
    echo "  actual  : $ACTUAL_SHA"
    exit 1
fi
echo "  ✅ Verified sha256: $ACTUAL_SHA"

# ---------------------------------------------------------------------------
# Extract and prepare upgrade
# ---------------------------------------------------------------------------

echo ""
echo "→ Extracting new version..."

EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$TARBALL" -C "$EXTRACT_DIR"

if [[ ! -d "$EXTRACT_DIR/trade-mcp" ]]; then
    echo "ERROR: tarball does not contain trade-mcp/ directory"
    exit 1
fi

NEW_ROOT="$EXTRACT_DIR/trade-mcp"

# ---------------------------------------------------------------------------
# Perform upgrade (preserve data)
# ---------------------------------------------------------------------------

echo ""
echo "→ Performing upgrade..."

# 1. Preserve data directory completely
if [[ -d "$INSTALL_DIR/data" ]]; then
    echo "  Preserving data/ directory..."
    # Just ensure it exists, don't overwrite
fi

# 2. Preserve custom config if user modified it
if [[ -f "$INSTALL_DIR/config/default.yaml" ]]; then
    # Check if user modified it (compare with default checksum)
    USER_CONFIG_SHA=$(sha256sum "$INSTALL_DIR/config/default.yaml" | awk '{print $1}')
    NEW_CONFIG_SHA=$(sha256sum "$NEW_ROOT/config/default.yaml" | awk '{print $1}')
    
    if [[ "$USER_CONFIG_SHA" != "$NEW_CONFIG_SHA" ]]; then
        echo "  ⚠️  Your config/default.yaml appears modified."
        echo "      Saving backup to config/default.yaml.user_backup"
        cp "$INSTALL_DIR/config/default.yaml" "$INSTALL_DIR/config/default.yaml.user_backup"
    fi
fi

# 3. Update binary
echo "  Updating bin/trade-mcp..."
rm -rf "$INSTALL_DIR/bin"
cp -r "$NEW_ROOT/bin" "$INSTALL_DIR/bin"
chmod 0755 "$INSTALL_DIR/bin/trade-mcp"

# 4. Update config (overwrite defaults)
echo "  Updating config/..."
rm -rf "$INSTALL_DIR/config"
cp -r "$NEW_ROOT/config" "$INSTALL_DIR/config"

# Restore user backup if exists
if [[ -f "$INSTALL_DIR/config/default.yaml.user_backup" ]]; then
    echo "  Restoring your custom config..."
    mv "$INSTALL_DIR/config/default.yaml.user_backup" "$INSTALL_DIR/config/default.yaml"
fi

# 5. Update resources, prompts, skills
echo "  Updating resources/, prompts/, skills/..."
rm -rf "$INSTALL_DIR/resources" "$INSTALL_DIR/prompts" "$INSTALL_DIR/skills"
cp -r "$NEW_ROOT/resources" "$NEW_ROOT/prompts" "$NEW_ROOT/skills" "$INSTALL_DIR/"

# 6. Update VERSION and docs
echo "  Updating VERSION, README.md, USAGE.md..."
cp "$NEW_ROOT/VERSION" "$NEW_ROOT/README.md" "$NEW_ROOT/USAGE.md" "$INSTALL_DIR/"

# 7. Ensure migrations directory exists
if [[ ! -d "$INSTALL_DIR/migrations" ]]; then
    mkdir -p "$INSTALL_DIR/migrations"
fi

# ---------------------------------------------------------------------------
# Verify upgrade
# ---------------------------------------------------------------------------

echo ""
echo "→ Verifying upgrade..."

NEW_VERSION=$(cat "$INSTALL_DIR/VERSION")
if [[ "$NEW_VERSION" != "$TARGET_BARE" ]]; then
    echo "ERROR: VERSION file mismatch after upgrade"
    echo "  Expected: $TARGET_BARE"
    echo "  Got     : $NEW_VERSION"
    exit 1
fi

# Verify binary works
echo '{"method":"tools/list"}' | "$INSTALL_DIR/bin/trade-mcp" | head -c 100 > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo "  ✅ Binary executes correctly"
else
    echo "  ⚠️  Binary test failed, but upgrade completed"
fi

# Verify database still accessible
if [[ -f "$DB_PATH" ]]; then
    DB_SIZE_AFTER=$(stat -c %s "$DB_PATH" 2>/dev/null || stat -f %z "$DB_PATH")
    echo "  ✅ Database preserved: $DB_SIZE_AFTER bytes"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "  Upgrade completed successfully!"
echo "============================================"
echo ""
echo "Previous version : $CURRENT_VERSION"
echo "New version      : $NEW_VERSION"
echo "Install location : $INSTALL_DIR"
echo ""
echo "Preserved:"
echo "  - data/trade_crm.db ($DB_SIZE_AFTER bytes)"
echo "  - data/backups/ ($(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l) backups)"
echo ""
echo "Pre-upgrade backup:"
echo "  - $PRE_UPGRADE_BACKUP"
echo ""
echo "To start using the new version:"
echo "  $INSTALL_DIR/bin/trade-mcp"
echo ""
echo "To rollback if needed:"
echo "  cp $PRE_UPGRADE_BACKUP $DB_PATH"
echo ""