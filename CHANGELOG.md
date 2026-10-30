# Changelog

All notable changes to this action are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the action
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-30

The first release.

### Added

- A composite action that installs the slcr CLI on Linux (x86_64 and ARM64)
  and macOS (Apple silicon and Intel) runners, verifies the download against
  the release's published SHA-256, and caches it in the runner's tool cache
  and the GitHub Actions cache.
- `command` runs `slcr check`, `slcr vet` (after `slcr tools install`),
  or `slcr render --expect-no-diff`, or only installs slcr (`none`).
- Inputs for the common flags: `deny-warnings`, `offline`, `jobs`, `files`,
  `expect-no-diff`, `install-tools`, and `args` for anything else.
- Verification of slcr's GitHub artifact attestation, on by default
  (`verify-attestation`). A verified install never reuses a cached binary
  that an unverified install wrote.
- The command's output in the job summary, and an error annotation when it
  fails.
- Outputs `version`, `path`, `cache-hit`, and `exit-code`.

[Unreleased]: https://github.com/wack/slcr-action/compare/v1.0.0...trunk
[1.0.0]: https://github.com/wack/slcr-action/releases/tag/v1.0.0
