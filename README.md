# THOR — Mac-to-Jetson Robotics Control Plane

<p align="center">
  <img src="Assets/jetson-thor.png" alt="NVIDIA Jetson Thor" width="600"/>
</p>

<p align="center">
  <strong>The first fully open-source macOS app for connecting Macs to NVIDIA Jetson devices.</strong>
  <br/>
  <em>Deploy ANIMA AI modules. Control Docker & ROS2. Monitor fleets. No terminal needed.</em>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#features">Features</a> &bull;
  <a href="#anima-modules">ANIMA Modules</a> &bull;
  <a href="#cli">CLI (thorctl)</a> &bull;
  <a href="#architecture">Architecture</a> &bull;
  <a href="#development">Development</a>
</p>

---

## Quick Start

```bash
# Clone and build
git clone https://github.com/RobotFlow-Labs/thorapp.git
cd thorapp
make build

# Start Jetson simulators (Docker)
make docker-up

# Run tests (50 tests across 7 suites)
make test

# Package and launch the app
make run

# Or install the CLI
make install-cli
thorctl health 8470
thorctl modules 8470
```

## Features

### 8-Tab Device Control

| Tab | What it does |
|-----|-------------|
| **Overview** | Live CPU, memory, disk, GPU metrics with auto-refresh and staleness indicators |
| **ANIMA** | Browse AI modules, compose pipelines, deploy with TensorRT, monitor status |
| **Files** | rsync delta sync, scp upload, drag-and-drop, SHA-256 verification |
| **Deploy** | Saved deploy profiles with preflight checks and step-by-step execution |
| **ROS2** | Node, topic, and service inspector with message types |
| **Docker** | Container list, start/stop/restart with confirmation, log viewer |
| **Logs** | System + agent log streaming with keyword filter and severity coloring |
| **History** | Event timeline + transfer history with verification status |

### Fleet Management
- Grid view with health rollup badges
- Environment filter (lab/field/staging/demo) + search
- Multi-select batch actions: health refresh, disconnect, ANIMA module check, pipeline stop
- Per-device result reporting

### Security
- **Trust-On-First-Use (TOFU)**: SSH host key fingerprint displayed and confirmed during enrollment
- **Keychain**: All credentials stored in macOS Keychain, never plaintext
- **Localhost-only agent**: API bound to 127.0.0.1, accessed via SSH tunnel
- **Confirmation dialogs**: Reboot, delete, container stop require explicit confirmation
- **Auto-reconnect**: Exponential backoff (2-32s) with configurable retry limits

### Onboarding
- 3-step welcome flow with prerequisite checks (SSH, rsync, Docker, Keychain, database)
- Quick Add presets for Docker simulators
- SSH key generation (ed25519) with public key clipboard copy
- Network discovery via mDNS and ARP scanning

## ANIMA Modules

THOR is designed to deploy [ANIMA](https://github.com/AIFLOWLABS) AI modules to Jetson devices:

```
                    ┌─────────────────────────────────┐
  THOR (Mac)        │  ANIMA Module (Jetson)           │
  ────────────      │  ┌─────────────────────────────┐ │
  Browse modules    │  │ Docker container             │ │
  Compose pipeline  │  │ TensorRT backend             │ │
  Deploy via SSH ──►│  │ ROS2 topics (in/out)         │ │
  Monitor health    │  │ Health: /anima/<mod>/health   │ │
                    │  └─────────────────────────────┘ │
                    └─────────────────────────────────┘
```

**Included simulated modules**: PETRA (depth perception), CHRONOS (tracking), PYGMALION (VLA)

Each module declares capabilities, ROS2 interfaces, hardware support, and performance profiles via `anima_module.yaml` manifests.

## CLI

```
thorctl — THOR CLI for Jetson device management

DEVICE COMMANDS:
  devices, ls                   List registered devices
  connect <host> [port]         Connect and show device info
  health [port]                 Check agent health
  capabilities, caps [port]     Show device capabilities
  metrics [port]                Show system metrics
  exec <port> <command>         Execute command on device
  docker [port]                 List Docker containers

ANIMA COMMANDS:
  anima-modules, modules [port] List ANIMA modules
  anima-status [port]           Show pipeline status
  anima-deploy <port> <yaml>    Deploy ANIMA pipeline
  anima-stop <port> [name]      Stop ANIMA pipeline

ROS2 COMMANDS:
  ros2-nodes [port]             List ROS2 nodes
  ros2-topics [port]            List ROS2 topics

MONITORING:
  watch [port] [interval]       Live metrics dashboard
  screenshot [filename]         Capture macOS screenshot
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  macOS                                              │
│  ┌──────────────┐     XPC      ┌──────────────┐    │
│  │  THOR.app    │◄────────────►│  THORCore    │    │
│  │  (SwiftUI)   │              │  (Helper)    │    │
│  └──────────────┘              └──────┬───────┘    │
│  ┌──────────────┐                     │             │
│  │  thorctl     │              SSH tunnel           │
│  │  (CLI)       │                     │             │
│  └──────────────┘                     │             │
└───────────────────────────────────────┼─────────────┘
                                        ▼
┌───────────────────────────────────────────────────────┐
│  Jetson Device                                        │
│  ┌──────────────────┐                                 │
│  │  THOR Agent       │  ◄── localhost:8470 HTTP/JSON  │
│  │  (Python/FastAPI) │      18 endpoints              │
│  └────────┬─────────┘                                 │
│     ┌─────┴─────┬──────────┬──────────┬────────┐      │
│     │ Docker    │ ROS2     │ GPU/sys  │ ANIMA  │      │
│     │ runtime   │ tooling  │ metrics  │ modules│      │
│     └───────────┴──────────┴──────────┴────────┘      │
└───────────────────────────────────────────────────────┘
```

### Project Structure

```
thorapp/                          72 files, 15k+ lines
├── Package.swift                 4 targets: THORApp, THORCore, THORctl, THORShared
├── Makefile                      Build, test, run, install, Docker, stats
├── Sources/
│   ├── THORApp/                  SwiftUI application
│   │   ├── THORApp.swift         @main — WindowGroup + MenuBarExtra + Settings
│   │   ├── Models/AppState.swift @Observable root state
│   │   ├── Views/                16 views (8 tabs + fleet + onboarding + settings + dialogs)
│   │   └── Services/             DeviceConnector, PipelineDeployer, FileTransfer, AgentInstaller,
│   │                             DebugBundleExporter, NetworkDiscovery, PrerequisiteChecker
│   ├── THORCore/                 Background helper service
│   ├── THORctl/                  CLI with 17 commands
│   └── THORShared/               Shared library
│       ├── Database/             GRDB manager + 3 migrations, 13 tables
│       ├── Keychain/             macOS Keychain wrapper
│       ├── Models/               11 record types + response models
│       ├── SSH/                  Session manager (actor) + host key verifier
│       └── Services/             Pipeline composer
├── Tests/                        50 tests across 7 suites
├── Agent/                        Python Jetson agent (18 endpoints)
├── Docker/                       Jetson simulator (Thor + Orin)
├── Scripts/                      Build, package, icon generation
└── .github/workflows/ci.yml     CI/CD pipeline
```

## Development

```bash
make build          # Debug build
make release        # Release build
make test           # All 50 tests
make test-unit      # Unit tests only (no Docker)
make run            # Package and launch app
make docker-up      # Start Jetson sims
make install-cli    # Install thorctl to /usr/local/bin
make stats          # Show project stats
make clean          # Clean build artifacts
```

## Supported Devices

| Device | Status | JetPack |
|--------|--------|---------|
| Jetson Thor | Primary | 6.1+ |
| Jetson Orin NX / Nano | Supported | 6.0+ |
| Jetson AGX Orin | Supported | 5.1+ |

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built by <a href="https://github.com/RobotFlow-Labs">RobotFlow Labs</a> &bull; An <a href="https://github.com/AIFLOWLABS">AIFLOW LABS</a> project
</p>
