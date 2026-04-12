#!/usr/bin/env bash
# THOR — Quick install script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
swift build -c release

# Install CLI
echo ""
echo "Installing thorctl to /usr/local/bin..."
mkdir -p /usr/local/bin
cp .build/release/thorctl /usr/local/bin/thorctl
chmod +x /usr/local/bin/thorctl

# Package app
echo ""
echo "Packaging THOR.app..."
SIGNING_MODE=adhoc Scripts/release/package_app.sh release

# Copy to /Applications
echo ""
if [[ -d "/Applications/THOR.app" ]]; then
    rm -rf "/Applications/THOR.app"
fi
cp -R THORApp.app "/Applications/THOR.app"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "  GUI:  open /Applications/THOR.app"
echo "  CLI:  thorctl help"
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
