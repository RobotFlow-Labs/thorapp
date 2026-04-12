#!/usr/bin/env bash
set -euo pipefail

MODE=${1:-all}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

wait_for_health() {
  local url="$1"
  local label="$2"
  local attempts="${3:-30}"

  for _ in $(seq 1 "$attempts"); do
    if curl -sf "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "ERROR: Timed out waiting for $label at $url" >&2
  return 1
}

case "$MODE" in
  unit)
    swift test --filter "DatabaseTests|PipelineComposerTests|RegistryFeatureTests|JetsonThorQuickStartSupportTests|JetsonThorProductionReadinessTests"
    swift test --filter versionSmoke
    exec swift test --filter helpSmoke
    ;;
  all)
    ;;
  *)
    echo "Usage: $(basename "$0") [all|unit]" >&2
    exit 1
    ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed. Install Docker Desktop or run 'make test-unit'." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: Docker daemon is not running.

THOR's full test suite depends on the local Jetson simulator containers.

Start Docker Desktop, then rerun:
  make test

If you only want the non-Docker suite:
  make test-unit
EOF
  exit 1
fi

echo "==> Starting Jetson simulators"
docker compose up -d --build

echo "==> Waiting for simulator health"
wait_for_health "http://127.0.0.1:8470/v1/health" "Thor simulator"
wait_for_health "http://127.0.0.1:8471/v1/health" "Orin simulator"

echo "==> Running swift test"
swift test
