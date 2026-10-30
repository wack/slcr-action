# Contributing

Issues and pull requests are welcome. For SLCR itself (the format and the
CLI), see [wack/slcr](https://github.com/wack/slcr).

## Layout

| Path | What it is |
| --- | --- |
| `action.yml` | The composite action: its inputs, outputs, and steps. |
| `scripts/resolve.sh` | Validates inputs, picks the release archive for the runner, and reads its SHA-256. |
| `scripts/install.sh` | Downloads, verifies, and installs slcr, unless a cache already has it, then puts it on `PATH`. |
| `scripts/run.sh` | Runs the slcr command and writes the job summary. |
| `scripts/lib.sh` | Helpers the scripts share. |
| `test/fixtures/project` | A small SLCR project the tests run against. Setting `GREET_BREAK=hello` or `GREET_BREAK=bye` breaks its MUST or SHOULD requirement. |
| `.github/workflows/ci.yml` | Lint and end-to-end tests. |
| `.github/workflows/release.yml` | Moves the major version tag when a release is published. |

## Conventions

- Keep logic in `scripts/`, where ShellCheck can see it, not inline in
  `action.yml`.
- Pass inputs to scripts through `env:`. Never use `${{ inputs.* }}` inside a
  `run:` script.
- Scripts must run on macOS's `/bin/bash`, which is version 3.2: no
  `mapfile`, no `${var,,}`, and no associative arrays. Under `set -u`, expand
  a possibly empty array as `${array[@]+"${array[@]}"}`.
- A function that can fail with `die` sets a variable instead of printing its
  result. Inside `$(...)`, the error annotation would be captured and the exit
  would end only the subshell.
- Pin every action to a full commit SHA, with its version in a comment.

## Checks

CI runs these on every pull request:

- **Lint:** [ShellCheck](https://www.shellcheck.net),
  [actionlint](https://github.com/rhysd/actionlint), and
  [zizmor](https://docs.zizmor.sh). To run them locally:

  ```sh
  shellcheck --external-sources scripts/*.sh test/fixtures/project/greet.sh
  actionlint
  zizmor --offline .
  ```

- **End-to-end tests:** the action itself, on Linux x86_64 and ARM64, macOS
  Apple silicon and Intel, and an Alpine container. The tests cover every
  command, the outputs, failures and their exit codes, input validation,
  caching across jobs, and attestation verification.

Add or update a test in `ci.yml` along with any change in behavior. Record
user-visible changes under "Unreleased" in [CHANGELOG.md](CHANGELOG.md).

## Releasing

1. In `CHANGELOG.md`, rename "Unreleased" to the new version and date.
2. Publish a GitHub release whose tag is that version, such as `v1.2.0`, and
   tick "Publish this Action to the GitHub Marketplace."
3. The `Release` workflow moves the major tag (`v1`) to the release. It
   doesn't move the tag for a prerelease, or for a release older than the
   newest one in its major version.

If a tag ruleset protects `v*` tags, allow GitHub Actions to bypass it, or the
workflow can't move the major tag.
