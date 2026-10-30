#!/bin/sh
# The program the demo specification describes. Setting GREET_BREAK to
# `hello` or `bye` breaks that behavior, so the action's own tests can make
# `slcr check` see an unsatisfied MUST or SHOULD requirement.
set -eu

if [ "${1:-}" = "--bye" ]; then
  shift
  if [ "${GREET_BREAK:-}" = "bye" ]; then
    echo "Bye."
  else
    echo "Goodbye, $1!"
  fi
elif [ "${GREET_BREAK:-}" = "hello" ]; then
  echo "Hi."
else
  echo "Hello, $1!"
fi
