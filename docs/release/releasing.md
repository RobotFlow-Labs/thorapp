# Releasing THOR

This repo is set up so a public release can be produced from a clean checkout without custom local steps.

## Local Checklist

1. Update `version.env`.
2. Update `CHANGELOG.md`.
3. Run:

```bash
make test
make dist
```

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

## Notes

- The default release flow uses ad-hoc signing unless `APP_IDENTITY` is set.
- Notarization is intentionally left as a later release-hardening step so the public repo can still ship testable artifacts immediately.
