#!/usr/bin/env bash
# THOR bootstrap installer.
# Stable public entrypoint kept at Scripts/install.sh for curl-based installs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/Package.swift" && -f "$SCRIPT_DIR/setup/install.sh" ]]; then
  exec "$SCRIPT_DIR/setup/install.sh" "$@"
fi

INSTALL_DIR="${INSTALL_DIR:-$HOME/.thor}"

echo "=== THOR Bootstrap Installer ==="
echo ""

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating existing installation at $INSTALL_DIR..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "Cloning thorapp into $INSTALL_DIR..."
  git clone https://github.com/RobotFlow-Labs/thorapp.git "$INSTALL_DIR"
fi

exec "$INSTALL_DIR/Scripts/setup/install.sh" "$@"
