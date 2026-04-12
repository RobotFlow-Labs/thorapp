#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/version.env" ]]; then
  source "$ROOT/version.env"
else
  MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
  BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP_NAME=${APP_NAME:-THORApp}
ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  ARCH_LIST=("$(uname -m)")
fi

if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
  ARTIFACT_ARCH="universal"
else
  ARTIFACT_ARCH="${ARCH_LIST[0]}"
fi

build_product_path() {
  local name="$1"
  local arch="$2"
  case "$arch" in
    arm64|x86_64) echo ".build/${arch}-apple-macosx/$CONF/$name" ;;
    *) echo ".build/$CONF/$name" ;;
  esac
}

create_binary() {
  local name="$1"
  local destination="$2"
  local binaries=()

  for arch in "${ARCH_LIST[@]}"; do
    swift build -c "$CONF" --arch "$arch" --product "$name"
    local source_path
    source_path=$(build_product_path "$name" "$arch")
    if [[ ! -f "$source_path" ]]; then
      echo "ERROR: Missing ${name} build for ${arch} at ${source_path}" >&2
      exit 1
    fi
    binaries+=("$source_path")
  done

  if [[ ${#binaries[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$destination"
  else
    cp "${binaries[0]}" "$destination"
  fi

  chmod +x "$destination"
}

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/THORApp-*.zip "$DIST_DIR"/thorctl-*.tar.gz "$DIST_DIR"/SHA256SUMS.txt

SIGNING_MODE="${SIGNING_MODE:-adhoc}" "$ROOT/Scripts/release/package_app.sh" "$CONF"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLI_BINARY="$TMP_DIR/thorctl"
create_binary "thorctl" "$CLI_BINARY"

APP_ZIP="$DIST_DIR/${APP_NAME}-${MARKETING_VERSION}-macos-${ARTIFACT_ARCH}.zip"
CLI_TAR="$DIST_DIR/thorctl-${MARKETING_VERSION}-macos-${ARTIFACT_ARCH}.tar.gz"
CHECKSUMS="$DIST_DIR/SHA256SUMS.txt"

ditto -c -k --sequesterRsrc --keepParent "$ROOT/${APP_NAME}.app" "$APP_ZIP"
tar -C "$TMP_DIR" -czf "$CLI_TAR" thorctl

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$APP_ZIP")" "$(basename "$CLI_TAR")" > "$(basename "$CHECKSUMS")"
)

echo "Created release artifacts:"
echo "  $APP_ZIP"
echo "  $CLI_TAR"
echo "  $CHECKSUMS"
