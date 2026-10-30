#!/usr/bin/env bash
# Validates the inputs, then resolves which slcr archive to install: the
# release tag, the runner's target triple, the archive's published SHA-256,
# and where it is installed. The SHA-256 keys the cache, so a tag that is
# moved to a new build (such as `edge`) is never served stale.

# shellcheck source=scripts/lib.sh
source "${GITHUB_ACTION_PATH:-$(dirname "$0")/..}/scripts/lib.sh"

validate_inputs
[[ "$INPUT_COMMAND" == none ]] || validate_working_directory

# Sets `target` to the release target triple built for this runner. dist
# builds no Windows archives, and Linux on ARM only for glibc.
resolve_target() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$arch" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) die "slcr has no release for the $arch architecture; use an x86_64 or ARM64 runner." ;;
  esac
  case "$os" in
    Linux)
      if [[ "$arch" == x86_64 ]]; then
        # Statically linked, so it runs in any job container, whatever its
        # C library.
        target=x86_64-unknown-linux-musl
      elif ldd --version 2>&1 | grep -qi musl; then
        die "slcr's ARM64 Linux release needs glibc, which this runner lacks (it uses musl, e.g. Alpine); use an x86_64 runner or a glibc-based container."
      else
        target=aarch64-unknown-linux-gnu
      fi
      ;;
    Darwin) target="$arch-apple-darwin" ;;
    *) die "slcr has no release for $os; use a Linux or macOS runner." ;;
  esac
}

# Sets `tag` to the latest stable release's, read from where GitHub
# redirects /releases/latest. Unlike the REST API, that needs no token and
# has no per-repository rate limit.
resolve_latest_tag() {
  local url
  url="$(curl --proto '=https' --tlsv1.2 --silent --show-error --fail --location --head \
    --retry 5 --retry-connrefused --connect-timeout 30 --max-time 60 \
    --output /dev/null --write-out '%{url_effective}' \
    "https://github.com/$SLCR_REPOSITORY/releases/latest")" ||
    die "Could not look up the latest slcr release."
  case "$url" in
    */releases/tag/?*) tag="${url##*/releases/tag/}" ;;
    *) die "Could not find the latest slcr release: https://github.com/$SLCR_REPOSITORY/releases/latest redirected to $url." ;;
  esac
}

version="$INPUT_VERSION"
# Trims surrounding whitespace.
version="${version#"${version%%[![:space:]]*}"}"
version="${version%"${version##*[![:space:]]}"}"
if [[ -z "$version" || "$version" == latest ]]; then
  resolve_latest_tag
elif [[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]]; then
  tag="v${version#v}"
else
  tag="$version"
fi
if [[ ! "$tag" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]]; then
  die "Input 'version' must be 'latest', a version such as '0.1.0', or a release tag, not '$version'."
fi

resolve_target
archive="slcr-$target.tar.xz"
checksum_url="https://github.com/$SLCR_REPOSITORY/releases/download/$tag/$archive.sha256"

tmp="$(mktemp -d "${RUNNER_TEMP:-/tmp}/slcr-action.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
status="$(download "$checksum_url" "$tmp/checksum")" ||
  die "Could not download $checksum_url."
case "$status" in
  200) ;;
  404) die "slcr release '$tag' has no $target archive, or does not exist: see https://github.com/$SLCR_REPOSITORY/releases." ;;
  *) die "Downloading $checksum_url failed with HTTP $status." ;;
esac
# dist writes `<sha256> *<archive>`.
sha256="$(cut -d ' ' -f 1 <"$tmp/checksum" | tr -d '\r\n')"
if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  die "$checksum_url does not hold a SHA-256 checksum."
fi

install_dir="${RUNNER_TOOL_CACHE:-${RUNNER_TEMP:-/tmp}}/slcr/$tag/$target"
# A persistent tool cache, as self-hosted runners have, may already hold
# this exact build.
installed=false
if [[ -x "$install_dir/slcr" && -f "$install_dir/.sha256" ]] &&
  [[ "$(cat "$install_dir/.sha256")" == "$sha256" ]]; then
  installed=true
fi

echo "slcr $tag for $target: $archive, SHA-256 $sha256"
set_output tag "$tag"
set_output target "$target"
set_output sha256 "$sha256"
set_output install-dir "$install_dir"
set_output installed "$installed"
set_output cache-key "slcr-$tag-$target-$sha256"
