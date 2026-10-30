# SLCR GitHub Action

[![CI](https://github.com/wack/slcr-action/actions/workflows/ci.yml/badge.svg)](https://github.com/wack/slcr-action/actions/workflows/ci.yml)

Check your [SLCR](https://slcr.dev) requirements in GitHub Actions. The action
installs the [`slcr`](https://github.com/wack/slcr) CLI, caches it, and runs
one of the commands CI needs:

- **`check`** runs every validator and fails if a requirement is unsatisfied.
- **`vet`** checks that specifications, validator files, and `SLCR.toml` are
  well formed, without running anything.
- **`render`** fails if a committed `SPEC.md` is out of date with its
  specification.

It's a [composite action](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action)
written in Bash. It has no JavaScript or Docker layer, and it runs on Linux and
macOS runners, including in job containers.

## Contents

- [Quick start](#quick-start)
- [Commands](#commands)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Examples](#examples)
- [Runners](#runners)
- [How slcr is installed and cached](#how-slcr-is-installed-and-cached)
- [Security](#security)
- [Versioning](#versioning)
- [Contributing](#contributing)
- [License](#license)

## Quick start

```yaml
name: Requirements

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  slcr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      # Validators run your project's own tools, such as a test runner, so
      # set those up before `check`.

      - name: Vet the specification
        uses: wack/slcr-action@v1
        with:
          command: vet
          deny-warnings: true

      - name: Check the requirements
        uses: wack/slcr-action@v1
        with:
          command: check
          deny-warnings: true

      - name: Check that SPEC.md is up to date
        uses: wack/slcr-action@v1
        with:
          command: render
```

Only the first step downloads slcr. Later steps in the job reuse it from the
runner's tool cache.

## Commands

Set the command with the `command` input. It defaults to `check`.

| `command` | Runs | Fails when |
| --- | --- | --- |
| `check` | `slcr check` | A validator can't run, or a MUST or MUST NOT requirement is unsatisfied. With `deny-warnings`, also on any warning, such as an unsatisfied SHOULD. |
| `vet` | `slcr tools install`, then `slcr vet` | A file can't be loaded or breaks an invariant. With `deny-warnings`, also on any warning. |
| `render` | `slcr render --expect-no-diff` | The Markdown doesn't hold exactly what its specification renders to. Set `expect-no-diff: false` to write the Markdown instead. |
| `none` | Nothing | Never. slcr is installed and put on `PATH` for later steps. |

`check` installs any tool descriptors `SLCR.toml` pins that the runner doesn't
have yet, unless `offline` is set. `vet` never fetches a descriptor itself, so
the action runs `slcr tools install` before vetting a project. That's the same
pattern as running `terraform init` before `terraform validate`. Turn it off
with `install-tools: false`.

Each command's output goes to the step log, and a copy goes to the
[job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/).
A failure also adds an error annotation to the run.

## Inputs

All inputs are optional.

| Input | Default | Description |
| --- | --- | --- |
| `command` | `check` | `check`, `vet`, `render`, or `none`. See [Commands](#commands). |
| `version` | `latest` | The slcr release to install. Use `latest` for the newest stable release, a version such as `0.1.0` or `v0.1.0`, or another release tag. Pin a version for reproducible builds. |
| `working-directory` | `.` | The directory to run slcr in. slcr looks for `SLCR.toml` there and in its parent directories. |
| `deny-warnings` | `false` | `check` and `vet`: fail on warnings too. |
| `offline` | `false` | `check`: never fetch a tool descriptor. A descriptor missing from the store fails the check. |
| `jobs` | number of CPUs | `check`: run at most this many validators at once. |
| `files` | | `vet`: the requirements files to vet, one per line. Leave it empty to vet the whole project. `render`: the specifications to render, one per line. Leave it empty to render `SPEC.slcr.toml`. |
| `expect-no-diff` | `true` | `render`: write nothing, and fail unless the Markdown is up to date. Set it to `false` to write the Markdown. |
| `install-tools` | `true` | `vet`: run `slcr tools install` first. Ignored when `files` is set. |
| `args` | | Extra arguments for the slcr command, such as `--log-level debug`. They're split on whitespace, and quotes aren't interpreted. |
| `cache` | `true` | Cache the slcr binary with the GitHub Actions cache. |
| `verify-attestation` | `false` | Verify the release archive's [build attestation](#security) before installing it. Needs the GitHub CLI (`gh`). |
| `github-token` | `${{ github.token }}` | The token `gh attestation verify` uses. It's used only when `verify-attestation` is `true`. |
| `color` | `true` | Color slcr's output in the log. The job summary is always plain text. |
| `job-summary` | `true` | Add the command's output to the job summary. |

Boolean inputs must be `true` or `false`. The action checks every input before
it downloads anything. If an input only applies to another command, the action
warns that it's ignored.

## Outputs

| Output | Description |
| --- | --- |
| `version` | The installed slcr version, such as `0.1.0`. |
| `path` | The absolute path of the slcr binary. |
| `cache-hit` | `true` if slcr came from the runner's tool cache or the Actions cache, `false` if it was downloaded. |
| `exit-code` | The slcr command's exit code. It's empty when `command` is `none`. To read it after a failure, use a later step with `if: failure()`, or set `continue-on-error`. |

## Examples

### Pin the slcr version

```yaml
- uses: wack/slcr-action@v1
  with:
    version: 0.1.0
```

### A project in a subdirectory

```yaml
- uses: wack/slcr-action@v1
  with:
    working-directory: services/api
```

### Validators that need a toolchain

Validators run your project's tools. The action doesn't install them, so set
them up first. This example is a Rust project whose validators run
`cargo nextest`:

```yaml
- uses: actions/checkout@v7
- uses: dtolnay/rust-toolchain@stable
- uses: taiki-e/install-action@cargo-nextest
- uses: wack/slcr-action@v1
  with:
    deny-warnings: true
    jobs: 4
```

### Vet specific files

```yaml
- uses: wack/slcr-action@v1
  with:
    command: vet
    files: |
      specs/api.slcr.yaml
      specs/cli.slcr.yaml
```

### Check several rendered specifications

`slcr render` takes one specification. The action renders each file in `files`
and reports every stale one before it fails.

```yaml
- uses: wack/slcr-action@v1
  with:
    command: render
    files: |
      specs/api.slcr.yaml
      specs/cli.slcr.yaml
```

### Publish the rendered Markdown

```yaml
- uses: wack/slcr-action@v1
  with:
    command: render
    expect-no-diff: false
    args: --output ${{ runner.temp }}/SPEC.md
- uses: actions/upload-artifact@v7
  with:
    name: spec
    path: ${{ runner.temp }}/SPEC.md
```

### Run slcr yourself

With `command: none`, the action only installs slcr. Later steps can then run
any slcr command, such as a check that writes a JSON report:

```yaml
- uses: wack/slcr-action@v1
  with:
    command: none
- run: slcr check --format json > slcr-report.json
- uses: actions/upload-artifact@v7
  if: always()
  with:
    name: slcr-report
    path: slcr-report.json
```

### React to a failed check

```yaml
- id: slcr
  uses: wack/slcr-action@v1
  continue-on-error: true
- if: steps.slcr.outputs.exit-code != '0'
  run: echo "Requirements are unsatisfied; see the job summary."
```

## Runners

| Runner | slcr build |
| --- | --- |
| Linux x86_64 (`ubuntu-*`) | `x86_64-unknown-linux-musl`, statically linked, so it runs in any job container |
| Linux ARM64 (`ubuntu-*-arm`) | `aarch64-unknown-linux-gnu`, which needs glibc 2.35 or newer |
| macOS Apple silicon (`macos-*`) | `aarch64-apple-darwin` |
| macOS Intel (`macos-*-intel`) | `x86_64-apple-darwin` |

slcr doesn't ship Windows builds, so on Windows the action fails with an
explanation.

GitHub-hosted runners have everything the action needs. Self-hosted runners
and job containers need `bash`, `curl`, `tar` with `xz`, and either
`sha256sum`, `shasum`, or `openssl`. Caching uses
[`actions/cache`](https://github.com/actions/cache) v6, which needs runner
version 2.327.1 or newer. For example, an Alpine container needs:

```yaml
container: alpine:3.22
steps:
  - run: apk add --no-cache bash curl tar xz
    shell: sh
  - uses: actions/checkout@v7
  - uses: wack/slcr-action@v1
```

## How slcr is installed and cached

1. **Resolve.** The action reads which tag `latest` points to from the
   redirect at `github.com/wack/slcr/releases/latest`. That needs no token and
   doesn't count against the REST API's rate limits. It then downloads the
   release's published `.sha256` checksum for the runner's archive.
2. **Reuse.** The archive's SHA-256 is part of the cache key, so a tag that
   moves to a new build is never served stale. The action looks for slcr in
   the runner's tool cache first, which lasts between jobs on self-hosted
   runners. If it isn't there, the action restores it from the Actions cache.
3. **Install.** On a cache miss, the action downloads the archive over HTTPS
   and checks it against the checksum. If `verify-attestation` is set, it also
   checks the archive's attestation. Then it extracts the binary into the tool
   cache. The binary is staged and moved into place, so an interrupted install
   never leaves a partial one behind.
4. **Save.** The action saves the cache right after installing, not in a
   post-job step. That way, a run whose `check` fails still caches slcr.

Then the action puts slcr on `PATH` for the rest of the job.

## Security

- **Checksums.** The action checks every download against the SHA-256 that
  the slcr release publishes before it extracts anything.
- **Build attestations.** slcr's release workflow attests each archive with
  [GitHub artifact attestations](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations).
  With `verify-attestation: true`, the action runs `gh attestation verify` on
  a downloaded archive. The archive must have been built by
  `wack/slcr/.github/workflows/release.yml` from the tag being installed. A
  binary restored from a cache was verified when it was first downloaded.
  Only tagged releases are attested, so `edge` can't be verified. On GitHub
  Enterprise Server, `github-token` must be a github.com token.
- **No script injection.** Inputs reach the action's scripts only as
  environment variables. They're never pasted into script text.
- **Pinned dependencies.** The action pins `actions/cache` to a full commit
  SHA. Dependabot keeps that pin current.
- **Least privilege.** The action needs only `contents: read`, to check out
  your code. It doesn't need a token unless you verify attestations.

For the strongest guarantee, pin the action to a full commit SHA too:

```yaml
- uses: wack/slcr-action@<commit-sha> # v1.0.0
```

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Versioning

Releases follow [Semantic Versioning](https://semver.org). Each release
`vX.Y.Z` also moves the major tag `vX`. Use `@v1` to get compatible updates,
or pin a full commit SHA if you want to review every update. A breaking change
to the action's inputs, outputs, or behavior means a new major version. A new
slcr release isn't a breaking change to the action, so pin `version` if you
need a fixed slcr. See [CHANGELOG.md](CHANGELOG.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) to learn how the action is tested and
released. For SLCR itself (the format and the CLI), see
[wack/slcr](https://github.com/wack/slcr).

## License

[MIT](LICENSE)
