# Releasing THOR

This repo is set up so a contributor smoke build or a production notarized release can be produced from a clean checkout without custom local steps.

Production release rule:

- Public tagged releases must be Developer ID signed and notarized.
- Ad-hoc signed artifacts are for contributor smoke testing only and must not be treated as production distribution artifacts.

## Local Checklist

1. Update `version.env`.
2. Update `CHANGELOG.md`.
3. Decide whether this is a contributor smoke build or a production notarized release.
4. Run:

```bash
make test-unit
make test
make dist
```

Run `make test` when Docker Desktop is available and you want the simulator-backed integration sweep.
`make dist` now runs the release verifier, so the local packaging path is checked before artifacts are published.

Artifacts are written to `dist/`:

- `THORApp-<version>-macos-<arch>.zip`
- `thorctl-<version>-macos-<arch>.tar.gz`
- `SHA256SUMS.txt`

## Universal Builds

For a universal local release build:

```bash
ARCHES="arm64 x86_64" Scripts/release/create_dist.sh release
```

## GitHub Release Flow

This repo includes `.github/workflows/release.yml`.

- `workflow_dispatch` builds release artifacts for manual smoke testing.
- Pushing a tag like `v0.1.0` builds the release bundle and attaches the `dist/` artifacts to a GitHub release.
- If Apple signing secrets are configured, the workflow builds a universal Developer ID signed app, notarizes it, staples it, and validates the stapled bundle before publishing.
- If Apple signing secrets are missing, `workflow_dispatch` still produces ad-hoc contributor smoke artifacts.
- If Apple signing secrets are missing on a tag push, the workflow now fails instead of publishing a public ad-hoc release.

## Install And Update

Public users should treat the tap as the primary install/update path:

```bash
brew tap RobotFlow-Labs/tap
brew install thorapp
brew upgrade thorapp
```

Source users can update by pulling the repo, rerunning the local test gates, and rebuilding the distributable artifacts.

## Notarization

For a locally notarized build, provide:

- `APP_IDENTITY`
- `NOTARY_KEY_ID`
- `NOTARY_ISSUER_ID`
- `NOTARY_KEY_PATH` or `NOTARY_KEY_BASE64`

Then run:

```bash
SIGNING_MODE=developer-id NOTARIZE_APP=1 make dist
```

## Notes

- The default release flow uses ad-hoc signing unless `APP_IDENTITY` is set.
- The repo can now produce notarized builds, but ad-hoc signed artifacts remain a contributor-only fallback path for workflows without Apple signing credentials.
- The Homebrew tap installs the CLI plus a `thorapp` launcher that opens the bundled GUI without needing to write into `/Applications`.
