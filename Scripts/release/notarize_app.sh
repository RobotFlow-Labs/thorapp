#!/usr/bin/env bash
set -euo pipefail

APP_PATH=${1:-}
ARCHIVE_PATH=${2:-}

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $(basename "$0") <path-to-app> [archive-path]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: App bundle not found: $APP_PATH" >&2
  exit 1
fi

: "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID to the App Store Connect API key ID}"
: "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID to the App Store Connect issuer ID}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  KEY_PATH="$NOTARY_KEY_PATH"
elif [[ -n "${NOTARY_KEY_BASE64:-}" ]]; then
  KEY_PATH="$TMP_DIR/AuthKey_${NOTARY_KEY_ID}.p8"
  printf '%s' "$NOTARY_KEY_BASE64" | base64 --decode > "$KEY_PATH"
else
  echo "ERROR: Set NOTARY_KEY_PATH or NOTARY_KEY_BASE64 for notarization" >&2
  exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
  echo "ERROR: Notary key not found at $KEY_PATH" >&2
  exit 1
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$TMP_DIR/$(basename "$APP_PATH").zip"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

xcrun notarytool submit "$ARCHIVE_PATH" \
  --key "$KEY_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait

xcrun stapler staple "$APP_PATH"

echo "Notarized and stapled: $APP_PATH"
