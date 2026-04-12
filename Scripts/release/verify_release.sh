#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
APP_PATH=${2:-}
APP_ZIP=${3:-}
CLI_TAR=${4:-}
CHECKSUMS=${5:-}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -f "$ROOT/version.env" ]]; then
  # Keep the verifier aligned with the packager's version source of truth.
  source "$ROOT/version.env"
fi

if [[ -z "$APP_PATH" || -z "$APP_ZIP" || -z "$CLI_TAR" || -z "$CHECKSUMS" ]]; then
  echo "Usage: $(basename "$0") <build-config> <app-path> <app-zip> <cli-tar> <checksums>" >&2
  exit 1
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
APP_ZIP="$(cd "$(dirname "$APP_ZIP")" && pwd)/$(basename "$APP_ZIP")"
CLI_TAR="$(cd "$(dirname "$CLI_TAR")" && pwd)/$(basename "$CLI_TAR")"
CHECKSUMS="$(cd "$(dirname "$CHECKSUMS")" && pwd)/$(basename "$CHECKSUMS")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: App bundle not found: $APP_PATH" >&2
  exit 1
fi

for artifact in "$APP_ZIP" "$CLI_TAR" "$CHECKSUMS"; do
  if [[ ! -f "$artifact" ]]; then
    echo "ERROR: Missing release artifact: $artifact" >&2
    exit 1
  fi
done

unzip -t "$APP_ZIP" >/dev/null
tar -tzf "$CLI_TAR" >/dev/null

if ! grep -q "$(basename "$APP_ZIP")" "$CHECKSUMS"; then
  echo "ERROR: Checksums file does not reference $(basename "$APP_ZIP")" >&2
  exit 1
fi

if ! grep -q "$(basename "$CLI_TAR")" "$CHECKSUMS"; then
  echo "ERROR: Checksums file does not reference $(basename "$CLI_TAR")" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "ERROR: Missing Info.plist in app bundle" >&2
  exit 1
fi

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

EXPECTED_VERSION="${MARKETING_VERSION:-0.1.0}"
PLIST_VERSION=$(plist_value "$INFO_PLIST" CFBundleShortVersionString)
if [[ "$PLIST_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "ERROR: Expected version $EXPECTED_VERSION in app bundle, found ${PLIST_VERSION:-<missing>}" >&2
  exit 1
fi

if [[ -n "${BUILD_NUMBER:-}" ]]; then
  PLIST_BUILD=$(plist_value "$INFO_PLIST" CFBundleVersion)
  if [[ "$PLIST_BUILD" != "$BUILD_NUMBER" ]]; then
    echo "ERROR: Expected build number $BUILD_NUMBER in app bundle, found ${PLIST_BUILD:-<missing>}" >&2
    exit 1
  fi
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

CLI_SMOKE_DIR="$TMP_DIR/cli-smoke"
mkdir -p "$CLI_SMOKE_DIR"
tar -xzf "$CLI_TAR" -C "$CLI_SMOKE_DIR"
CLI_BINARY="$CLI_SMOKE_DIR/thorctl"
if [[ ! -x "$CLI_BINARY" ]]; then
  echo "ERROR: CLI binary not found or not executable after extraction: $CLI_BINARY" >&2
  exit 1
fi

if ! CLI_VERSION_OUTPUT=$("$CLI_BINARY" version 2>&1); then
  echo "ERROR: thorctl version smoke failed: $CLI_VERSION_OUTPUT" >&2
  exit 1
fi

if [[ -z "$CLI_VERSION_OUTPUT" ]]; then
  echo "ERROR: thorctl version returned no output" >&2
  exit 1
fi

if [[ "${NOTARIZE_APP:-0}" == "1" || "${SIGNING_MODE:-}" == "developer-id" ]]; then
  if command -v xcrun >/dev/null 2>&1; then
    xcrun stapler validate "$APP_PATH" || true
    spctl -a -vvv --type execute "$APP_PATH"
  fi
fi

echo "Verified release artifacts for $CONF:"
echo "  $(basename "$APP_ZIP")"
echo "  $(basename "$CLI_TAR")"
echo "  $(basename "$CHECKSUMS")"
