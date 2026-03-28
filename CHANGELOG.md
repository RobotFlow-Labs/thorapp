# Changelog

All notable changes to THOR are documented here.

## [0.1.0] - 2026-03-28

### Initial Release

**The first open-source macOS control center for NVIDIA Jetson devices.**

#### App (THORApp)
- Native SwiftUI macOS app with grouped sidebar navigation
- 12 feature panels: Overview, System, Power, Hardware, Docker, ROS2, ANIMA, Files, Deploy, GPU & Models, Logs, History
- Menu bar integration with status-driven icon
- Onboarding flow with prerequisite checks
- Fleet view with batch operations
- Network discovery (mDNS + ARP)
- SSH key generation (ed25519)
- Trust-On-First-Use host key verification
- macOS Keychain credential storage
- Auto-reconnect with exponential backoff
- Destructive action confirmations
- Debug bundle export
- Real-time metrics with staleness indicators

#### CLI (thorctl)
- 25 commands for terminal-based Jetson management
- Power mode control, system info, disk usage
- Camera, GPIO, I2C, USB, serial port detection
- GPU info, TensorRT engine listing, model inventory
- ROS2 node/topic/service listing, topic echo
- Docker container management
- ANIMA module browsing and pipeline management
- Live metrics watch mode
- Screenshot capture

#### Agent (Python)
- 50 HTTP/JSON endpoints across 10 router modules
- Power, system, storage, network, hardware, ROS2, GPU, Docker, logs, ANIMA
- Background process manager for ROS2 launch, bag recording, TRT conversion
- Simulation mode for Docker-based testing
- Multipart file upload for model deployment

#### Infrastructure
- GRDB SQLite database with 13 tables, 3 migrations
- Docker Compose with 2 Jetson simulators (Thor + Orin)
- ROS2 Humble with live talker/listener demo
- Docker-in-Docker support
- GitHub Actions CI/CD
- Homebrew formula
- 71 tests across 8 suites (all against real Docker sim)
- MIT License
