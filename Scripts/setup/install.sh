#!/usr/bin/env bash
# THOR — Quick install script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

resolve_install_dir() {
    local env_override="$1"
    local primary="$2"
    local fallback="$3"

    if [[ -n "$env_override" ]]; then
        mkdir -p "$env_override"
        echo "$env_override"
        return 0
    fi

    if mkdir -p "$primary" 2>/dev/null && [[ -w "$primary" ]]; then
        echo "$primary"
        return 0
    fi

    mkdir -p "$fallback"
    echo "$fallback"
}

echo "=== THOR Installer ==="
echo ""

# Check prerequisites
if ! command -v swift &>/dev/null; then
    echo "ERROR: Swift not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "WARNING: THOR is optimized for Apple Silicon (arm64)."
    echo "  Your architecture: $(uname -m)"
fi

# Clone or update if the script is running outside a checked-out repo.
if [[ ! -f "$ROOT_DIR/Package.swift" ]]; then
    INSTALL_DIR="${INSTALL_DIR:-$HOME/.thor}"
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "Updating existing installation..."
        git -C "$INSTALL_DIR" pull --ff-only
    else
        echo "Cloning thorapp..."
        git clone https://github.com/RobotFlow-Labs/thorapp.git "$INSTALL_DIR"
    fi
    ROOT_DIR="$INSTALL_DIR"
fi

cd "$ROOT_DIR"

# Build
echo ""
echo "Building THOR..."
Scripts/dev/swiftw build -c release

BIN_DIR="$(resolve_install_dir "${INSTALL_BIN_DIR:-}" "/usr/local/bin" "$HOME/.local/bin")"
APP_DIR="$(resolve_install_dir "${INSTALL_APP_DIR:-}" "/Applications" "$HOME/Applications")"

# Package app
echo ""
echo "Packaging THOR.app..."
SIGNING_MODE=adhoc Scripts/package_app.sh release

# Install CLI
echo ""
echo "Installing thorctl to $BIN_DIR..."
install -m 0755 .build/release/thorctl "$BIN_DIR/thorctl"

# Copy app bundle
echo ""
echo "Installing THOR.app to $APP_DIR..."
if [[ -d "$APP_DIR/THOR.app" ]]; then
    rm -rf "$APP_DIR/THOR.app"
fi
ditto THORApp.app "$APP_DIR/THOR.app"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "  GUI:  open \"$APP_DIR/THOR.app\""
echo "  CLI:  $BIN_DIR/thorctl help"
if [[ "$BIN_DIR" != "/usr/local/bin" ]]; then
    echo ""
    echo "Add $BIN_DIR to your PATH if it is not already present."
fi
echo ""
echo "Quick start:"
echo "  1. thorctl connect YOUR_JETSON_IP"
echo "  2. thorctl health"
echo "  3. thorctl power"
echo ""
echo "Docker simulators (no hardware needed):"
echo "  cd $ROOT_DIR && docker compose up -d"
echo "  thorctl connect localhost 8470"
echo ""
