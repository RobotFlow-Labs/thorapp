.PHONY: build release test test-unit run package dist tap-smoke install-cli clean docker-up docker-down docker-logs lint icon help

# Default target
help:
	@echo "THOR — Mac-to-Jetson Robotics Control Plane"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Development:"
	@echo "  build       Build all targets (debug)"
	@echo "  release     Build all targets (release)"
	@echo "  test        Run the full suite (starts Docker sims if daemon is available)"
	@echo "  test-unit   Run unit tests only (no Docker needed)"
	@echo "  run         Build, package, and launch the app"
	@echo "  package     Package .app bundle (release)"
	@echo "  dist        Build release artifacts into dist/"
	@echo "  tap-smoke   Install the formula from a temporary local tap"
	@echo "  icon        Generate app icon from assets"
	@echo "  clean       Remove build artifacts"
	@echo ""
	@echo "Docker Simulator:"
	@echo "  docker-up   Start Jetson simulators"
	@echo "  docker-down Stop Jetson simulators"
	@echo "  docker-logs View simulator logs"
	@echo ""
	@echo "CLI:"
	@echo "  install-cli Install thorctl to /usr/local/bin"
	@echo "  thorctl     Run thorctl with ARGS (e.g. make thorctl ARGS='health')"
	@echo ""
	@echo "Quality:"
	@echo "  lint        Run SwiftLint (if installed)"
	@echo "  stats       Show project statistics"

# Build
build:
	swift build

release:
	swift build -c release

# Test
test:
	Scripts/dev/run_tests.sh all

test-unit:
	Scripts/dev/run_tests.sh unit

# Run
run: package
	@pkill -f "THORApp.app/Contents/MacOS/THORApp" 2>/dev/null || true
	@open THORApp.app

package:
	SIGNING_MODE=adhoc Scripts/package_app.sh release

dist:
	SIGNING_MODE=adhoc Scripts/release/create_dist.sh release

tap-smoke:
	Scripts/release/tap_smoke.sh

icon:
	Scripts/dev/generate_icon.sh

# Docker
docker-up:
	docker compose up -d

docker-down:
	docker compose down

docker-logs:
	docker compose logs -f

# CLI
install-cli: release
	@echo "Installing thorctl to /usr/local/bin..."
	@cp .build/release/thorctl /usr/local/bin/thorctl
	@echo "Done. Run 'thorctl help' to get started."

thorctl:
	swift run thorctl $(ARGS)

# Quality
lint:
	@which swiftlint >/dev/null 2>&1 && swiftlint lint --strict || echo "SwiftLint not installed. Run: brew install swiftlint"

stats:
	@echo "=== THOR Project Stats ==="
	@echo "Files:    $$(find . -type f -not -path './.build/*' -not -path './THORApp.app/*' -not -path './.git/*' -not -name '.DS_Store' -not -name 'Package.resolved' | wc -l | tr -d ' ')"
	@echo "Lines:    $$(find . -type f -not -path './.build/*' -not -path './THORApp.app/*' -not -path './.git/*' -not -name '.DS_Store' -not -name 'Package.resolved' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $$1}')"
	@echo "Commits:  $$(git log --oneline | wc -l | tr -d ' ')"
	@echo "Tests:    $$(swift test 2>&1 | grep 'Test run' | grep -oE '[0-9]+ tests' | head -1)"
	@echo "TODOs:    $$(rg TODO Sources/ 2>/dev/null | wc -l | tr -d ' ')"

# Clean
clean:
	swift package clean
	rm -rf THORApp.app .build/THOR.iconset dist
