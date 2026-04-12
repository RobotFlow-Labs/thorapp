#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TAP_NAME="${TAP_NAME:-codex/thor-smoke}"
FORMULA_NAME="${FORMULA_NAME:-thorapp}"
FORMULA_SOURCE="${FORMULA_SOURCE:-$ROOT/Formula/${FORMULA_NAME}.rb}"
WORK_DIR="$(mktemp -d)"
LOCAL_SOURCE_ARCHIVE="$WORK_DIR/${FORMULA_NAME}-source.tar.gz"

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
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

brew uninstall --force --ignore-dependencies "$TAP_NAME/$FORMULA_NAME" >/dev/null 2>&1 || true
brew untap "$TAP_NAME" >/dev/null 2>&1 || true
rm -rf "$TAP_DIR"

tar -czf "$LOCAL_SOURCE_ARCHIVE" \
  --exclude=".git" \
  --exclude=".build" \
  --exclude=".swiftpm" \
  --exclude="dist" \
  --exclude="THORApp.app" \
  -C "$ROOT" .
LOCAL_SOURCE_SHA="$(shasum -a 256 "$LOCAL_SOURCE_ARCHIVE" | awk '{print $1}')"
LOCAL_SOURCE_URL="file://${LOCAL_SOURCE_ARCHIVE}"

brew tap-new "$TAP_NAME" >/dev/null
mkdir -p "$TAP_DIR/Formula"
TAP_FORMULA="$TAP_DIR/Formula/${FORMULA_NAME}.rb"
cp "$FORMULA_SOURCE" "$TAP_FORMULA"

ruby - "$TAP_FORMULA" "$LOCAL_SOURCE_URL" "$LOCAL_SOURCE_SHA" <<'RUBY'
formula_path, source_url, source_sha = ARGV
content = File.read(formula_path)

replacement = <<~BLOCK.chomp
  url "#{source_url}"
    sha256 "#{source_sha}"
BLOCK

unless content.sub!(
  /url "https:\/\/github\.com\/RobotFlow-Labs\/thorapp\.git",\n\s+tag: "v[^"]+"/,
  replacement
)
  abort("ERROR: Unable to rewrite formula URL for local tap smoke validation")
end

File.write(formula_path, content)
RUBY

brew install --build-from-source "$TAP_NAME/$FORMULA_NAME"

brew test "$TAP_NAME/$FORMULA_NAME"

FORMULA_PREFIX="$(brew --prefix "$TAP_NAME/$FORMULA_NAME")"
THORCTL="$FORMULA_PREFIX/bin/thorctl"
THORAPP="$FORMULA_PREFIX/bin/thorapp"

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

LAUNCH_TARGET="$(
  ruby -e 'content = File.read(ARGV[0]); match = content.match(/open -a "([^"]+)"/); puts(match ? match[1] : "")' "$THORAPP"
)"

if [[ -z "$LAUNCH_TARGET" || ! -d "$LAUNCH_TARGET" ]]; then
  echo "ERROR: thorapp launcher does not point at an installed app bundle" >&2
  exit 1
fi

echo "Tap smoke install passed for $TAP_NAME/$FORMULA_NAME"
echo "  $VERSION_OUTPUT"
