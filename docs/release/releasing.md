# Releasing THOR

This repo is set up so a public release can be produced from a clean checkout without custom local steps.

## Local Checklist

1. Update `version.env`.
2. Update `CHANGELOG.md`.
3. Run:

```bash
make test-unit
make dist
```

Run `make test` as well when Docker Desktop is available and you want the simulator-backed integration sweep.
`make dist` now runs the release verifier, so the ad-hoc fallback path is checked before artifacts are published.

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
- If Apple signing secrets are missing, the workflow falls back to the ad-hoc signed release path instead of failing late.

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
- The repo can now produce notarized builds, but ad-hoc signed artifacts remain the fallback path for contributors without Apple signing credentials.
- The Homebrew tap installs the CLI plus a `thorapp` launcher that opens the bundled GUI without needing to write into `/Applications`.
