# THOR Development Rules

## Adding Features

Every new Jetson control feature must follow this pipeline:

1. **Agent endpoint** — Python router in `Agent/routers/`, wraps a Linux command
2. **Response model** — Codable struct in `Sources/THORShared/Models/`
3. **AgentClient method** — in `Sources/THORShared/SSH/AgentClient.swift`
4. **SwiftUI view** — in `Sources/THORApp/Views/`, wired to sidebar in DeviceDetailView
5. **thorctl command** — in `Sources/THORctl/main.swift`
6. **Integration test** — in `Tests/`, hitting real Docker sim (NO mocks)
7. **Docker sim update** — if the feature needs new packages or stubs

## Testing Rules

- ALL tests must hit the real Docker Jetson simulator
- Zero mock data in tests
- Test both success and error paths
- Start Docker sims before testing: `make docker-up`
- Run `make test` after every change

## Build Rules

- `swift build` must have 0 errors AND 0 warnings
- `swift build -c release` must succeed
- Test with `make test` (71+ tests must pass)
- Package with `make run` before pushing

## Python Agent Rules

- Each domain gets its own router file in `Agent/routers/`
- Use `sim.is_sim()` to return plausible fake data in Docker sim
- ROS2 commands must use `_ros2_cmd()` helper (sources setup.bash)
- Dangerous commands must be blocked (rm -rf, mkfs, etc.)
- Background processes use `process_manager.py`

## SwiftUI Rules

- One view per file
- Use `@Environment(AppState.self)` for shared state
- Use `GroupBox` for card-style layouts
- Use system colors (Color(.secondarySystemFill), .primary, .secondary)
- Auto-refresh data with `.task` + timer for live panels
- Destructive actions require confirmation dialogs

## CLI Rules

- Every agent endpoint should have a corresponding thorctl command
- Output should be human-readable tables, not raw JSON
- Use `AgentClient(port:)` directly — no SSH needed for CLI
