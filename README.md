# THOR — Mac-to-Jetson Robotics Control Plane

<p align="center">
  <img src="Assets/jetson-thor.png" alt="NVIDIA Jetson Thor" width="600"/>
</p>

<p align="center">
  <strong>The first fully open-source macOS app for connecting Macs to NVIDIA Jetson devices.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> &bull;
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#architecture">Architecture</a> &bull;
  <a href="#development">Development</a> &bull;
  <a href="#docker-simulator">Docker Simulator</a> &bull;
  <a href="#roadmap">Roadmap</a>
</p>

---

THOR replaces fragmented terminal workflows with a native macOS control plane for Jetson-based robotics development. Connect, deploy, debug, and manage your Jetson Thor and Orin devices — without ever opening Terminal.

## Features

- **Native macOS** — SwiftUI on Apple Silicon. Menu bar integration, Keychain storage, system notifications.
- **Zero terminal dependency** — Device discovery, SSH management, file sync, and runtime control from a GUI.
- **Secure by default** — SSH credentials stored in macOS Keychain. Trust-on-first-use host key verification. Localhost-only agent API tunneled over SSH.
- **Multi-device ready** — Architecture designed for fleet management from day one, even while shipping single-device workflows first.
- **Jetson-aware** — Understands JetPack versions, GPU metrics, Docker runtimes, and ROS2 stacks natively.
- **Open source** — MIT licensed. Built by [RobotFlow Labs](https://github.com/RobotFlow-Labs).

## Supported Devices

| Device | Status |
|--------|--------|
| Jetson Thor | Primary target |
| Jetson Orin NX / Nano | Supported |
| Jetson AGX Orin | Supported |
| Other Jetson variants | Best-effort |

## Quick Start

### Prerequisites

- macOS 14+ (Sonoma) on Apple Silicon
- Swift 6.2+ toolchain (`xcode-select --install` or [swift.org](https://swift.org/install))
- Docker Desktop (for the Jetson simulator)

### Build and Run

```bash
# Clone
git clone https://github.com/RobotFlow-Labs/thorapp.git
cd thorapp

# Build
swift build

# Run tests
swift test

# Package into .app bundle and launch
Scripts/compile_and_run.sh
```

### Start the Jetson Simulator

No Jetson hardware? No problem. Spin up simulated devices with Docker:

```bash
# Start two simulated Jetsons (Thor + Orin)
docker compose up -d

# Verify they're running
docker compose ps

# Test SSH connectivity
ssh -p 2222 jetson@localhost    # password: jetson
ssh -p 2223 jetson@localhost    # password: jetson (Orin sim)

# Test agent API
curl http://localhost:8470/v1/health
curl http://localhost:8470/v1/capabilities
curl http://localhost:8470/v1/metrics

# Tear down
docker compose down
```

### Add a Device in THOR

1. Launch the app (`Scripts/compile_and_run.sh`)
2. Click **+** in the sidebar
3. Enter:
   - **Name**: `Jetson Thor Sim`
   - **Hostname**: `localhost`
   - **Port**: `2222`
   - **Username**: `jetson`
   - **Auth**: Password — `jetson`
4. Click **Add Device**

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  macOS                                              │
│                                                     │
│  ┌──────────────┐     XPC      ┌──────────────┐    │
│  │  THOR.app    │◄────────────►│  THORCore    │    │
│  │  (SwiftUI)   │              │  (Helper)    │    │
│  └──────────────┘              └──────┬───────┘    │
│                                       │             │
│                                  SSH tunnel         │
│                                       │             │
└───────────────────────────────────────┼─────────────┘
                                        │
                                        ▼
┌───────────────────────────────────────────────────────┐
│  Jetson Device                                        │
│                                                       │
│  ┌──────────────────┐                                 │
│  │  THOR Agent       │  ◄── localhost:8470 HTTP/JSON  │
│  │  (Python/FastAPI) │                                │
│  └────────┬─────────┘                                 │
│           │                                           │
│     ┌─────┴─────┬──────────┬──────────┐               │
│     │ Docker    │ ROS2     │ GPU/sys  │               │
│     │ runtime   │ tooling  │ metrics  │               │
│     └───────────┴──────────┴──────────┘               │
└───────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| UI Framework | SwiftUI + MenuBarExtra | Best macOS integration, menu bar, Keychain, notifications |
| Background Service | THORCore via SMAppService | Long-running SSH sessions survive app closure |
| App-to-Helper IPC | NSXPCConnection | Native macOS process boundary |
| Remote Transport | SSH (OpenSSH CLI) | No extra Jetson network exposure, leverages existing trust |
| Jetson Agent | Python 3 + FastAPI | Simplest bootstrap on Jetson Ubuntu, fast iteration |
| Agent Binding | localhost only (127.0.0.1) | Accessed via SSH tunnel — never exposed on network |
| Local Database | SQLite via GRDB | Explicit migrations, cross-process safe, predictable |
| Secrets | macOS Keychain | Never plaintext, OS-managed encryption |
| Remote Operations | Typed jobs with lifecycle | Progress UI, retries, audit trail, fleet-safe |

### Project Structure

```
thorapp/
├── Package.swift                 # SwiftPM — 3 targets
├── Sources/
│   ├── THORApp/                  # SwiftUI application
│   │   ├── THORApp.swift         # @main — WindowGroup + MenuBarExtra + Settings
│   │   ├── Models/AppState.swift # @Observable root state
│   │   └── Views/                # 7 views (list, detail, add, menubar, settings)
│   ├── THORCore/                 # Background helper service
│   │   └── main.swift            # Service entry point
│   └── THORShared/               # Shared library
│       ├── Database/             # GRDB manager + 9-table migration
│       ├── Keychain/             # macOS Keychain wrapper
│       ├── Models/               # 7 record types (Device, Job, Transfer, etc.)
│       └── SSH/                  # SSH session manager (actor, ControlMaster)
├── Tests/THORTests/              # Swift Testing suite
├── Agent/                        # Python Jetson agent (FastAPI)
│   └── main.py                   # /v1/health, /v1/capabilities, /v1/metrics, /v1/exec
├── Docker/                       # Jetson device simulator
│   ├── Dockerfile.jetson-sim     # Ubuntu 22.04 + SSH + Python agent
│   └── entrypoint.sh
├── docker-compose.yml            # 2 simulated Jetsons (Thor + Orin)
├── Scripts/
│   ├── package_app.sh            # Build + package .app bundle
│   └── compile_and_run.sh        # Dev loop: kill, build, package, launch
├── Assets/
│   └── jetson-thor.png
└── version.env                   # Marketing version + build number
```

### Database Schema

9 tables covering the full device lifecycle:

| Table | Purpose |
|-------|---------|
| `devices` | Managed device registry |
| `device_identities` | Host keys, serial numbers, agent IDs |
| `device_compatibility_snapshots` | JetPack, Docker, ROS2, GPU capabilities |
| `connection_states` | Live connection status per device |
| `jobs` | Typed remote operations with lifecycle |
| `job_events` | Audit trail for job state transitions |
| `transfer_records` | File sync history with verification |
| `runtime_profiles` | Deploy and launch configurations |
| `operator_preferences` | User settings and shortcuts |

## Development

### Build Commands

```bash
swift build                          # Debug build
swift build -c release               # Release build
swift test                           # Run test suite
Scripts/package_app.sh               # Package .app bundle (release)
Scripts/compile_and_run.sh           # Full dev loop: build, package, launch
Scripts/compile_and_run.sh --test    # Run tests before launching
```

### Jetson Agent Development

```bash
cd Agent
pip install fastapi uvicorn psutil   # or use uv
python main.py                       # Starts on 127.0.0.1:8470
```

### Docker Simulator

```bash
docker compose up -d                 # Start Thor + Orin simulators
docker compose logs -f jetson-sim    # Watch logs
docker compose down                  # Stop all
```

| Service | SSH Port | Agent Port | Simulated Model |
|---------|----------|------------|-----------------|
| `jetson-sim` | 2222 | 8470 | Jetson Thor |
| `jetson-orin-sim` | 2223 | 8471 | Jetson Orin NX |

**Default credentials**: `jetson` / `jetson`

## Roadmap

THOR is built in waves, each adding a layer of capability:

| Milestone | What | Status |
|-----------|------|--------|
| **M0** | Architecture freeze + first vertical slice | **In Progress** |
| **M1** | Single-device managed endpoint (discovery, enrollment, SSH) | Planned |
| **M2** | Dashboard + menu bar control surface | Planned |
| **M3** | Delta file sync + artifact delivery | Planned |
| **M4** | Docker + ROS2 runtime orchestration | Planned |
| **M5** | Live logs, telemetry, ROS2 graph, debug export | Planned |
| **M6** | Fleet view, batch actions, AI pipeline launchers | Planned |

See [`sub_prds/`](../sub_prds/) for the full breakdown of each milestone.

## Contributing

THOR is open source under the MIT license. We welcome contributions.

1. Fork the repo
2. Create a feature branch
3. `swift build && swift test`
4. Submit a PR

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built by <a href="https://github.com/RobotFlow-Labs">RobotFlow Labs</a> &bull; An <a href="https://github.com/AIFLOWLABS">AIFLOW LABS</a> project
</p>
