#!/usr/bin/env bash
# Runs the slcr command the `command` input names, streaming its output to
# the log, and adds that output to the job summary.

# shellcheck source=scripts/lib.sh
source "${GITHUB_ACTION_PATH:-$(dirname "$0")/..}/scripts/lib.sh"

: "${SLCR_BIN:?}"
# resolve.sh has already validated every input, before anything was
# downloaded; this step is given only the inputs it reads.

validate_working_directory
cd -- "$INPUT_WORKING_DIRECTORY"

if [[ "$INPUT_COLOR" == true ]]; then
  color=always
else
  color=never
fi

# `args`, split on whitespace. `read` neither globs nor interprets quotes.
extra=()
if [[ -n "$INPUT_ARGS" ]]; then
  read -r -d '' -a extra <<<"$INPUT_ARGS" || true
fi

# `files`, one per line, with surrounding whitespace and blank lines dropped.
files=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] || files+=("$line")
done <<<"$INPUT_FILES"

# Inputs that only one command reads are reported when set for another, so a
# misplaced setting doesn't go silently unused.
ignored() {
  warn "Input '$1' only applies to $2, so it is ignored for 'command: $INPUT_COMMAND'."
}
if [[ "$INPUT_COMMAND" != check ]]; then
  [[ "$INPUT_OFFLINE" == false ]] || ignored offline "'check'"
  [[ -z "$INPUT_JOBS" ]] || ignored jobs "'check'"
fi
if [[ "$INPUT_COMMAND" == check ]]; then
  [[ ${#files[@]} -eq 0 ]] || ignored files "'vet' and 'render'"
fi
if [[ "$INPUT_COMMAND" == render ]]; then
  [[ "$INPUT_DENY_WARNINGS" == false ]] || ignored deny-warnings "'check' and 'vet'"
else
  [[ "$INPUT_EXPECT_NO_DIFF" == true ]] || ignored expect-no-diff "'render'"
fi

tmp="$(mktemp -d "${RUNNER_TEMP:-/tmp}/slcr-action.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Prints a file for the job summary: without ANSI escapes, HTML-escaped,
# and cut to its last 64 KiB, well under the summary's 1 MiB limit.
summarize() {
  local file="$1" limit=65536
  if [[ "$(wc -c <"$file")" -gt "$limit" ]]; then
    echo "… (earlier output cut; the step log has all of it)"
  fi
  tail -c "$limit" "$file" |
    sed -e $'s/\033\\[[0-9;?]*[A-Za-z]//g' | html_escape
}

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Runs `slcr "$@"`, streaming stdout and stderr to the log while capturing
# each, and records its exit code in `code`.
run_slcr() {
  local out="$tmp/stdout" err="$tmp/stderr" display arg
  display=slcr
  for arg in "$@"; do
    if [[ "$arg" =~ ^[0-9A-Za-z_./=:@%+,-]+$ ]]; then
      display="$display $arg"
    else
      display="$display $(printf '%q' "$arg")"
    fi
  done
  echo "$ $display"
  code=0
  # stderr goes through the inner pipe and stdout through fd 3 to the outer
  # one; with pipefail, the pipeline fails with slcr's exit code.
  { "$SLCR_BIN" --enable-colors "$color" "$@" 2>&1 1>&3 3>&- | tee "$err" >&2 3>&-; } 3>&1 |
    tee "$out" || code=$?

  if [[ "$code" -ne 0 ]]; then
    # The title is the subcommand alone, which holds nothing a property
    # value would need escaped.
    printf '::error title=slcr %s::%s\n' "$1" \
      "$(escape_data "$display failed with exit code $code; its diagnostics are in the step log.")"
  fi

  if [[ "$INPUT_JOB_SUMMARY" == true && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      printf '### <code>%s</code> ' "$(printf '%s' "$display" | html_escape)"
      if [[ "$code" -eq 0 ]]; then
        printf '✅ passed\n\n'
      else
        printf '❌ failed (exit code %s)\n\n' "$code"
      fi
      if [[ -s "$out" ]]; then
        printf '<pre>\n'
        summarize "$out"
        printf '</pre>\n\n'
      fi
      if [[ -s "$err" ]]; then
        printf '<details><summary>Diagnostics</summary>\n\n<pre>\n'
        summarize "$err"
        printf '</pre>\n\n</details>\n\n'
      fi
    } >>"$GITHUB_STEP_SUMMARY"
  fi
}

status=0
case "$INPUT_COMMAND" in
  check)
    args=(check)
    [[ "$INPUT_DENY_WARNINGS" == false ]] || args+=(--deny-warnings)
    [[ "$INPUT_OFFLINE" == false ]] || args+=(--offline)
    [[ -z "$INPUT_JOBS" ]] || args+=(--jobs "$INPUT_JOBS")
    run_slcr "${args[@]}" ${extra[@]+"${extra[@]}"}
    status="$code"
    ;;
  vet)
    # Vetting a project looks for the descriptors SLCR.toml pins in the
    # descriptor store, which starts out empty on a fresh runner.
    if [[ ${#files[@]} -eq 0 && "$INPUT_INSTALL_TOOLS" == true ]]; then
      run_slcr tools install
      status="$code"
    fi
    if [[ "$status" -eq 0 ]]; then
      args=(vet)
      [[ "$INPUT_DENY_WARNINGS" == false ]] || args+=(--deny-warnings)
      if [[ ${#files[@]} -gt 0 ]]; then
        run_slcr "${args[@]}" ${extra[@]+"${extra[@]}"} -- "${files[@]}"
      else
        run_slcr "${args[@]}" ${extra[@]+"${extra[@]}"}
      fi
      status="$code"
    fi
    ;;
  render)
    args=(render)
    [[ "$INPUT_EXPECT_NO_DIFF" == false ]] || args+=(--expect-no-diff)
    if [[ ${#files[@]} -eq 0 ]]; then
      run_slcr "${args[@]}" ${extra[@]+"${extra[@]}"}
      status="$code"
    else
      # `slcr render` takes one file; every one is rendered, even after a
      # failure, so a single run reports each stale file.
      for file in "${files[@]}"; do
        run_slcr "${args[@]}" ${extra[@]+"${extra[@]}"} -- "$file"
        [[ "$status" -ne 0 ]] || status="$code"
      done
    fi
    ;;
esac

set_output exit-code "$status"
exit "$status"
