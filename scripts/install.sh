#!/usr/bin/env bash
# Installs the slcr archive resolve.sh chose, unless the tool cache or the
# Actions cache already held it: downloads it, checks it against its
# published SHA-256 (and, if asked, its build attestation), and extracts the
# binary. Then puts slcr on PATH.

# shellcheck source=scripts/lib.sh
source "${GITHUB_ACTION_PATH:-$(dirname "$0")/..}/scripts/lib.sh"

: "${SLCR_TAG:?}" "${SLCR_TARGET:?}" "${SLCR_SHA256:?}" "${SLCR_INSTALL_DIR:?}"

# Whether the install directory holds the expected build.
is_installed() {
  [[ -x "$SLCR_INSTALL_DIR/slcr" && -f "$SLCR_INSTALL_DIR/.sha256" ]] &&
    [[ "$(cat "$SLCR_INSTALL_DIR/.sha256")" == "$SLCR_SHA256" ]]
}

install_slcr() {
  local archive="slcr-$SLCR_TARGET.tar.xz"
  local url="https://github.com/$SLCR_REPOSITORY/releases/download/$SLCR_TAG/$archive"
  local status binary parent stage

  tmp="$(mktemp -d "${RUNNER_TEMP:-/tmp}/slcr-action.XXXXXX")"

  echo "Downloading $url"
  status="$(download "$url" "$tmp/$archive")" || die "Could not download $url."
  [[ "$status" == 200 ]] || die "Downloading $url failed with HTTP $status."

  sha256_of "$tmp/$archive"
  if [[ "$sha256" != "$SLCR_SHA256" ]]; then
    die "$archive has SHA-256 $sha256, but release $SLCR_TAG publishes $SLCR_SHA256."
  fi
  echo "Verified SHA-256 $sha256"

  if [[ "$INPUT_VERIFY_ATTESTATION" == true ]]; then
    command -v gh >/dev/null 2>&1 ||
      die "verify-attestation needs the GitHub CLI (gh), which is not on PATH."
    echo "Verifying the build attestation of $archive"
    GH_HOST=github.com gh attestation verify "$tmp/$archive" \
      --repo "$SLCR_REPOSITORY" \
      --signer-workflow "$SLCR_RELEASE_WORKFLOW" \
      --source-ref "refs/tags/$SLCR_TAG" ||
      die "$archive has no valid attestation that wack/slcr's release workflow built it from tag $SLCR_TAG."
    echo "Verified the build attestation"
  fi

  mkdir "$tmp/extract"
  if ! tar -xJf "$tmp/$archive" -C "$tmp/extract"; then
    if ! command -v xz >/dev/null 2>&1; then
      die "Could not extract $archive: tar needs xz, which is not on PATH (on Debian and Ubuntu, install xz-utils)."
    fi
    die "Could not extract $archive."
  fi
  binary="$tmp/extract/slcr-$SLCR_TARGET/slcr"
  [[ -f "$binary" ]] || die "$archive holds no slcr-$SLCR_TARGET/slcr."

  # Staged beside the install directory and moved into place, so that an
  # interrupted install never leaves a partial one behind.
  parent="$(dirname "$SLCR_INSTALL_DIR")"
  mkdir -p "$parent"
  stage="$(mktemp -d "$parent/.install.XXXXXX")"
  mv "$binary" "$stage/slcr"
  chmod 755 "$stage/slcr"
  printf '%s\n' "$SLCR_SHA256" >"$stage/.sha256"
  rm -rf "$SLCR_INSTALL_DIR"
  mv "$stage" "$SLCR_INSTALL_DIR"
}

tmp=""
trap '[[ -z "$tmp" ]] || rm -rf "$tmp"' EXIT

echo "::group::Installing slcr $SLCR_TAG ($SLCR_TARGET)"
cache_hit=false
downloaded=false
if [[ "${SLCR_TOOL_CACHE_HIT:-}" == true ]] && is_installed; then
  echo "Found in the tool cache: $SLCR_INSTALL_DIR"
  cache_hit=true
elif [[ "${SLCR_ACTIONS_CACHE_HIT:-}" == true ]] && is_installed; then
  echo "Restored from the Actions cache: $SLCR_INSTALL_DIR"
  cache_hit=true
else
  install_slcr
  downloaded=true
  echo "Installed to $SLCR_INSTALL_DIR"
fi

version="$("$SLCR_INSTALL_DIR/slcr" version)" ||
  die "The installed slcr ($SLCR_INSTALL_DIR/slcr) does not run on this runner."
version="${version#v}"
echo "slcr $version"
echo "::endgroup::"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$SLCR_INSTALL_DIR" >>"$GITHUB_PATH"
fi
set_output version "$version"
set_output path "$SLCR_INSTALL_DIR/slcr"
set_output cache-hit "$cache_hit"
set_output downloaded "$downloaded"
