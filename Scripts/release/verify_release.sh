#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
APP_PATH=${2:-}
APP_ZIP=${3:-}
CLI_TAR=${4:-}
CHECKSUMS=${5:-}
UPDATE_MANIFEST=${6:-}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -f "$ROOT/version.env" ]]; then
  # Keep the verifier aligned with the packager's version source of truth.
  source "$ROOT/version.env"
fi

if [[ -z "$APP_PATH" || -z "$APP_ZIP" || -z "$CLI_TAR" || -z "$CHECKSUMS" || -z "$UPDATE_MANIFEST" ]]; then
  echo "Usage: $(basename "$0") <build-config> <app-path> <app-zip> <cli-tar> <checksums> <update-manifest>" >&2
  exit 1
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
APP_ZIP="$(cd "$(dirname "$APP_ZIP")" && pwd)/$(basename "$APP_ZIP")"
CLI_TAR="$(cd "$(dirname "$CLI_TAR")" && pwd)/$(basename "$CLI_TAR")"
CHECKSUMS="$(cd "$(dirname "$CHECKSUMS")" && pwd)/$(basename "$CHECKSUMS")"
UPDATE_MANIFEST="$(cd "$(dirname "$UPDATE_MANIFEST")" && pwd)/$(basename "$UPDATE_MANIFEST")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: App bundle not found: $APP_PATH" >&2
  exit 1
fi

for artifact in "$APP_ZIP" "$CLI_TAR" "$CHECKSUMS" "$UPDATE_MANIFEST"; do
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

APP_SHA=$(awk -v artifact="$(basename "$APP_ZIP")" '$2 == artifact { print $1 }' "$CHECKSUMS")
if [[ -z "$APP_SHA" ]]; then
  echo "ERROR: Checksums file does not contain a SHA for $(basename "$APP_ZIP")" >&2
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

python3 - <<'PY' "$UPDATE_MANIFEST" "$APP_SHA" "$PLIST_VERSION" "${BUILD_NUMBER:-0}" "$(basename "$APP_ZIP")"
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
expected_sha = sys.argv[2]
expected_version = sys.argv[3]
expected_build = int(sys.argv[4])
expected_archive = sys.argv[5]

with manifest_path.open("r", encoding="utf-8") as handle:
    manifest = json.load(handle)

required = ["bundleIdentifier", "version", "build", "archiveName", "sha256"]
missing = [key for key in required if key not in manifest]
if missing:
    raise SystemExit(f"ERROR: Update manifest is missing keys: {', '.join(missing)}")

if manifest["bundleIdentifier"] != "com.robotflowlabs.thor":
    raise SystemExit(f"ERROR: Unexpected bundle identifier in update manifest: {manifest['bundleIdentifier']}")
if manifest["version"] != expected_version:
    raise SystemExit(f"ERROR: Update manifest version mismatch: expected {expected_version}, found {manifest['version']}")
if int(manifest["build"]) != expected_build:
    raise SystemExit(f"ERROR: Update manifest build mismatch: expected {expected_build}, found {manifest['build']}")
if manifest["archiveName"] != expected_archive:
    raise SystemExit(f"ERROR: Update manifest archive mismatch: expected {expected_archive}, found {manifest['archiveName']}")
if manifest["sha256"] != expected_sha:
    raise SystemExit("ERROR: Update manifest SHA mismatch")
PY

echo "Verified release artifacts for $CONF:"
echo "  $(basename "$APP_ZIP")"
echo "  $(basename "$CLI_TAR")"
echo "  $(basename "$CHECKSUMS")"
echo "  $(basename "$UPDATE_MANIFEST")"
