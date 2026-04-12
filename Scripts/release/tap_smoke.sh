#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TAP_NAME="${TAP_NAME:-codex/thor-smoke}"
FORMULA_NAME="${FORMULA_NAME:-thorapp}"
FORMULA_SOURCE="${FORMULA_SOURCE:-$ROOT/Formula/${FORMULA_NAME}.rb}"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_FROM_API=1
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew is required for tap smoke validation" >&2
  exit 1
fi

if [[ ! -f "$FORMULA_SOURCE" ]]; then
  echo "ERROR: Formula not found: $FORMULA_SOURCE" >&2
  exit 1
fi

TAP_OWNER="${TAP_NAME%%/*}"
TAP_REPO="${TAP_NAME##*/}"
if [[ "$TAP_OWNER" == "$TAP_REPO" ]]; then
  echo "ERROR: TAP_NAME must be in owner/repo form, got: $TAP_NAME" >&2
  exit 1
fi

BREW_REPO="$(brew --repository)"
TAP_DIR="$BREW_REPO/Library/Taps/${TAP_OWNER}/homebrew-${TAP_REPO}"

cleanup() {
  brew uninstall --force --ignore-dependencies "$TAP_NAME/$FORMULA_NAME" >/dev/null 2>&1 || true
  brew untap "$TAP_NAME" >/dev/null 2>&1 || true
  rm -rf "$TAP_DIR"
}
trap cleanup EXIT

brew uninstall --force --ignore-dependencies "$TAP_NAME/$FORMULA_NAME" >/dev/null 2>&1 || true
brew untap "$TAP_NAME" >/dev/null 2>&1 || true
rm -rf "$TAP_DIR"

brew tap-new "$TAP_NAME" >/dev/null
mkdir -p "$TAP_DIR/Formula"
cp "$FORMULA_SOURCE" "$TAP_DIR/Formula/${FORMULA_NAME}.rb"

brew install --build-from-source "$TAP_NAME/$FORMULA_NAME"

brew test "$TAP_NAME/$FORMULA_NAME"

PREFIX="$(brew --prefix)"
THORCTL="$PREFIX/bin/thorctl"
THORAPP="$PREFIX/bin/thorapp"

if [[ ! -x "$THORCTL" ]]; then
  echo "ERROR: Installed thorctl not found at $THORCTL" >&2
  exit 1
fi

if [[ ! -x "$THORAPP" ]]; then
  echo "ERROR: Installed thorapp launcher not found at $THORAPP" >&2
  exit 1
fi

VERSION_OUTPUT=$("$THORCTL" version)
if [[ -z "$VERSION_OUTPUT" ]]; then
  echo "ERROR: thorctl version returned no output" >&2
  exit 1
fi

if ! grep -q "open -a \"${PREFIX}/THORApp.app\"" "$THORAPP"; then
  echo "ERROR: thorapp launcher does not point at the installed app bundle" >&2
  exit 1
fi

echo "Tap smoke install passed for $TAP_NAME/$FORMULA_NAME"
echo "  $VERSION_OUTPUT"
