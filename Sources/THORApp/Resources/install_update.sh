#!/usr/bin/env bash
set -euo pipefail

PID="${1:-}"
STAGED_APP="${2:-}"
TARGET_APP="${3:-/Applications/THORApp.app}"

if [[ -z "$PID" || -z "$STAGED_APP" ]]; then
  echo "usage: $(basename "$0") <pid> <staged-app> [target-app]" >&2
  exit 1
fi

TARGET_PARENT="$(dirname "$TARGET_APP")"
STAGING_ROOT="$(dirname "$STAGED_APP")"

wait_for_exit() {
  local attempts=0
  while kill -0 "$PID" >/dev/null 2>&1; do
    sleep 1
    attempts=$((attempts + 1))
    if [[ "$attempts" -gt 120 ]]; then
      break
    fi
  done
}

install_payload() {
  rm -rf "$TARGET_APP"
  mkdir -p "$TARGET_PARENT"
  /usr/bin/ditto "$STAGED_APP" "$TARGET_APP"
  /usr/bin/xattr -cr "$TARGET_APP" >/dev/null 2>&1 || true
}

wait_for_exit

if [[ -w "$TARGET_PARENT" || ( -e "$TARGET_APP" && -w "$TARGET_APP" ) ]]; then
  install_payload
else
  export THOR_UPDATER_STAGED_APP="$STAGED_APP"
  export THOR_UPDATER_TARGET_APP="$TARGET_APP"
  export THOR_UPDATER_TARGET_PARENT="$TARGET_PARENT"
  /usr/bin/osascript <<'APPLESCRIPT'
set stagedApp to system attribute "THOR_UPDATER_STAGED_APP"
set targetApp to system attribute "THOR_UPDATER_TARGET_APP"
set targetParent to system attribute "THOR_UPDATER_TARGET_PARENT"
set installCommand to "/bin/rm -rf " & quoted form of targetApp & "; /bin/mkdir -p " & quoted form of targetParent & "; /usr/bin/ditto " & quoted form of stagedApp & " " & quoted form of targetApp & "; /usr/bin/xattr -cr " & quoted form of targetApp & " >/dev/null 2>&1 || true"
do shell script installCommand with administrator privileges
APPLESCRIPT
fi

/usr/bin/open "$TARGET_APP"
/bin/rm -rf "$STAGING_ROOT"
