# Contributing to THOR

Thank you for your interest in contributing to THOR! This project aims to be the best open-source control center for NVIDIA Jetson devices on macOS.

## Getting Started

```bash
git clone https://github.com/RobotFlow-Labs/thorapp.git
cd thorapp
make build
make test
make docker-up   # Start Jetson simulators
make run          # Launch the app
```

## Development Setup

- **macOS 14+** (Sonoma) on Apple Silicon
- **Swift 6.2+** — `xcode-select --install`
- **Docker Desktop** — for Jetson simulators

## How to Contribute

### Bug Reports

Open an [issue](https://github.com/RobotFlow-Labs/thorapp/issues) with:
- Steps to reproduce
- Expected vs actual behavior
- macOS version, Swift version
- Relevant logs or screenshots

### Feature Requests

Open an issue with the `enhancement` label describing:
- The use case
- Which Jetson model(s) it applies to
- How it would work in the UI and/or CLI

### Pull Requests

1. Fork the repo and create your branch from `main`
2. Write code following existing patterns
3. Add tests for new endpoints and features
4. Ensure `make test` passes (all 71+ tests)
5. Ensure `swift build` has 0 warnings
6. Update the README if you add user-facing features
7. Submit a PR with a clear description

### Code Style

- **Swift**: Follow Apple API Design Guidelines. Use `@Observable`, `@MainActor`, structured concurrency.
- **Python**: Follow PEP 8. Use type hints where practical.
- **Views**: One view per file. Use `GroupBox` for cards, system colors, 8pt spacing grid.
- **Tests**: Use Swift Testing framework (`#expect`, `#require`). Test against real Docker sim.
- **No mocks**: All integration tests hit the real Docker Jetson simulator.

### Adding a New Agent Endpoint

1. Create or modify a router in `Agent/routers/`
2. Add the response model in `Sources/THORShared/Models/`
3. Add the client method in `Sources/THORShared/SSH/AgentClient.swift`
4. Add a SwiftUI view or panel
5. Add a thorctl command in `Sources/THORctl/main.swift`
6. Add integration tests in `Tests/`
7. Update the Docker simulator if needed

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
