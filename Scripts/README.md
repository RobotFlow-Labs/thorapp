# Script Layout

THOR keeps shell entrypoints under `Scripts/` and groups them by purpose so the repo stays readable when published.

## Canonical Paths

- `Scripts/dev/compile_and_run.sh`
  Development loop that rebuilds, packages, relaunches, and optionally runs tests.
- `Scripts/dev/generate_icon.sh`
  Generates `Icon.icns` from the Jetson hero image or a fallback graphic.
- `Scripts/release/package_app.sh`
  Produces a signed or ad-hoc signed `THORApp.app` bundle from SwiftPM outputs.
- `Scripts/release/create_dist.sh`
  Produces zipped app + CLI release artifacts in `dist/` with SHA-256 checksums and the `THORApp-update.json` updater manifest.
- `Scripts/setup/install.sh`
  Installs `THORApp.app` into `/Applications` (or a writable fallback) and installs `thorctl` from a checked-out repo.
- `Scripts/jetson-thor/thor_serial.sh`
  Opens the Jetson AGX Thor debug or OEM-config serial console.
- `Scripts/jetson-thor/bootstrap_ssh.sh`
  Bootstraps SSH keys and passwordless sudo on a fresh Jetson.

## Compatibility Wrappers

The following legacy paths are intentionally kept so existing docs, Homebrew, and local automation do not break:

- `Scripts/compile_and_run.sh`
- `Scripts/generate_icon.sh`
- `Scripts/install.sh`
- `Scripts/package_app.sh`

New docs and automation should prefer the canonical grouped paths above.
