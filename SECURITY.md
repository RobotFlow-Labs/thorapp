# Security Policy

THOR is a macOS control plane for Jetson devices, so security issues can affect both the operator workstation and the managed robots. Please report vulnerabilities privately.

## Supported Versions

We currently support security fixes for the latest release on `main` and the most recent tagged release series.

| Version | Supported |
|---------|-----------|
| `main` | Yes |
| Latest tagged release | Yes |
| Older tags | Best effort only |

## Reporting a Vulnerability

Please do not open a public GitHub issue for a security vulnerability.

Instead, report it privately to:

- `security@robotflowlabs.com`

Include:

- affected THOR version or commit
- impact and attack scenario
- reproduction steps or proof of concept
- any suggested mitigation if you have one

## What to Expect

- We will acknowledge receipt as quickly as possible.
- We will validate the report and assess severity.
- We will coordinate a fix and release plan before public disclosure.

## Scope

Security reports are especially valuable for:

- SSH trust, host key verification, and local tunnel handling
- credential storage and Keychain integration
- agent install/bootstrap flows
- release signing, packaging, and update trust
- Docker/ROS2/device command execution boundaries

If you are validating a release artifact, include the exact download URL, checksum, and notarization status if available.

Do not use the fallback ad-hoc release path for production deployment on real hardware. It exists to keep contributor builds unblocked, not to replace notarized distribution.
