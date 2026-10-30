# shellcheck shell=bash disable=SC2034 # Variables here are used by the scripts that source it.
# Helpers shared by the action's scripts, which source this file.
#
# The scripts run on every runner the action supports, including macOS,
# whose /bin/bash is 3.2: no `mapfile`, no `${var,,}`, no associative
# arrays, and `"${array[@]}"` on an empty array is an unbound variable
# under `set -u`, so it is written `${array[@]+"${array[@]}"}`.

set -euo pipefail

# The repository slcr is released from.
readonly SLCR_REPOSITORY="wack/slcr"
# The workflow that builds and attests slcr's release archives.
readonly SLCR_RELEASE_WORKFLOW="wack/slcr/.github/workflows/release.yml"

# Escapes a workflow command's message, as the runner expects.
escape_data() {
  # Patterns and replacements are variables because bash 3.2 keeps quotes
  # inside a quoted `${s//pattern/replacement}` literally.
  local s="$1" pct='%' cr=$'\r' lf=$'\n'
  local pct_esc='%25' cr_esc='%0D' lf_esc='%0A'
  s="${s//$pct/$pct_esc}"
  s="${s//$cr/$cr_esc}"
  s="${s//$lf/$lf_esc}"
  printf '%s' "$s"
}

# Annotates the run with an error and exits.
die() {
  printf '::error title=slcr-action::%s\n' "$(escape_data "$*")"
  exit 1
}

warn() {
  printf '::warning title=slcr-action::%s\n' "$(escape_data "$*")"
}

# Writes a step output.
set_output() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  else
    printf '%s=%s\n' "$name" "$value"
  fi
}

# Checks that input `name` holds `true` or `false`.
require_bool() {
  local name="$1" value="$2"
  case "$value" in
    true | false) ;;
    *) die "Input '$name' must be 'true' or 'false', not '$value'." ;;
  esac
}

# Checks every input both scripts read, so a mistake fails the step before
# anything is downloaded.
validate_inputs() {
  case "$INPUT_COMMAND" in
    check | vet | render | none) ;;
    *) die "Input 'command' must be one of 'check', 'vet', 'render', or 'none', not '$INPUT_COMMAND'." ;;
  esac
  require_bool deny-warnings "$INPUT_DENY_WARNINGS"
  require_bool offline "$INPUT_OFFLINE"
  require_bool expect-no-diff "$INPUT_EXPECT_NO_DIFF"
  require_bool install-tools "$INPUT_INSTALL_TOOLS"
  require_bool cache "$INPUT_CACHE"
  require_bool verify-attestation "$INPUT_VERIFY_ATTESTATION"
  require_bool color "$INPUT_COLOR"
  require_bool job-summary "$INPUT_JOB_SUMMARY"
  if [[ -n "$INPUT_JOBS" && ! "$INPUT_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    die "Input 'jobs' must be a positive integer, not '$INPUT_JOBS'."
  fi
}

# Checks that the directory slcr is to run in exists.
validate_working_directory() {
  [[ -d "$INPUT_WORKING_DIRECTORY" ]] ||
    die "Input 'working-directory' names '$INPUT_WORKING_DIRECTORY', which is not a directory."
}

# Whether `dir` holds an install of the archive whose SHA-256 is `sha256`
# that this run can use. With verify-attestation on, that also means one
# whose attestation was verified when it was downloaded, so a build cached
# by a run that didn't verify is never used by one that does.
is_installed() {
  local dir="$1" sha256="$2"
  [[ -x "$dir/slcr" && -f "$dir/.sha256" ]] &&
    [[ "$(cat "$dir/.sha256")" == "$sha256" ]] &&
    [[ "$INPUT_VERIFY_ATTESTATION" == false || -f "$dir/.attested" ]]
}

# Downloads `url` to `dest` with retries on transient failures, and prints
# the final HTTP status. Fails only when the transfer itself fails.
download() {
  local url="$1" dest="$2"
  curl --proto '=https' --tlsv1.2 --silent --show-error --location \
    --retry 5 --retry-connrefused --connect-timeout 30 --max-time 300 \
    --output "$dest" --write-out '%{http_code}' "$url"
}

# Sets `sha256` to the SHA-256 of a file. (A function that can `die` sets a
# variable rather than printing its result: in a command substitution, the
# error annotation would be captured and the exit only end the subshell.)
sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256="$(sha256sum "$file" | cut -d ' ' -f 1)"
  elif command -v shasum >/dev/null 2>&1; then
    sha256="$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
  elif command -v openssl >/dev/null 2>&1; then
    sha256="$(openssl dgst -sha256 -r "$file" | cut -d ' ' -f 1)"
  else
    die "Found no SHA-256 tool (sha256sum, shasum, or openssl) to verify the slcr download."
  fi
}
