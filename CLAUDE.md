# THOR — Jetson Control Center for macOS

## What This Is
THOR is a native macOS app (SwiftUI + Swift Concurrency) that serves as the control center for NVIDIA Jetson devices. It manages power modes, Docker containers, ROS2 nodes, cameras, GPIO, AI model deployment, file sync, and system administration — all from your Mac, no terminal needed.

**First fully open-source Mac app for Jetson device management.**

## Architecture

```
macOS (THOR.app + thorctl)
├── THORApp (SwiftUI, @main)
│   ├── 12 feature panels via grouped sidebar
│   ├── 8 services (DeviceConnector, PipelineDeployer, etc.)
│   └── Menu bar integration
├── THORShared (library)
│   ├── Database/ (GRDB, 13 tables, 3 migrations)
│   ├── SSH/ (actor, ControlMaster, HostKeyVerifier, AgentClient)
│   ├── Keychain/ (macOS credential storage)
│   └── Models/ (50+ response types)
├── THORctl (CLI, 25 commands)
└── THORCore (background helper skeleton)

Jetson Device (Docker sim or real hardware)
└── THOR Agent (Python FastAPI, 50 endpoints, 10 routers)
    ├── power.py, system.py, storage.py, network.py
    ├── hardware.py, ros2.py, gpu.py
    ├── docker.py, logs.py, anima.py
    ├── sim.py (simulation state)
    └── process_manager.py (background processes)
```

## Dev Commands
```bash
make build          # swift build (debug)
make release        # swift build -c release
make test           # swift test (71 tests)
make run            # Package + launch .app
make docker-up      # Start Docker Jetson sims
make docker-down    # Stop sims
make install-cli    # Install thorctl to /usr/local/bin
make stats          # Project stats
make clean          # Clean artifacts
```

## Conventions
- Use `rg` (ripgrep) over `grep`
- Swift 6.2+, strict concurrency, @Observable for state
- SwiftUI views: one per file, GroupBox for cards, system colors
- Agent routers: one per domain, use `APIRouter` prefix
- Tests: Swift Testing framework, ALL against real Docker sim — zero mocks
- Every new feature needs: agent endpoint + response model + AgentClient method + view + thorctl command + test

## Feature Sidebar Layout
```
DEVICE          RUNTIME         OPERATIONS     OBSERVE
├ Overview      ├ Docker        ├ Files         ├ Logs
├ System        ├ ROS2          ├ Deploy        └ History
├ Power         └ ANIMA         └ GPU & Models
└ Hardware
```

## Key Files
- `Package.swift` — 4 targets: THORApp, THORCore, THORctl, THORShared
- `Agent/main.py` — FastAPI app importing 10 routers
- `Sources/THORShared/SSH/AgentClient.swift` — 50+ endpoint methods
- `Sources/THORShared/Models/JetsonResponses.swift` — All typed responses
- `Sources/THORApp/Views/DeviceDetailView.swift` — Main device view with sidebar
- `docker-compose.yml` — 2 Jetson sims (Thor:2222/8470, Orin:2223/8471)
- `Makefile` — All dev workflows

## Supported Devices
- Jetson Thor (JetPack 7.0+) — primary
- Jetson AGX Orin / Orin NX / Orin Nano (JetPack 5.1+)

## Bundle ID
`com.robotflowlabs.thor`

# currentDate
Today's date is 2026-03-28.
