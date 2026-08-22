#!/usr/bin/env bash
set -euo pipefail

executable="${1:-.build/debug/Pesty}"
test_dir="$(mktemp -d)"
out_file="$(mktemp)"
run_id="update-termination-$(date +%s)"
suite="com.bifrostproxy.pesty.$run_id"
test_pid=""

cleanup() {
  if [[ -n "$test_pid" ]] && /bin/kill -0 "$test_pid" 2>/dev/null; then
    /bin/kill -TERM "$test_pid" 2>/dev/null || true
  fi
  defaults delete "$suite" >/dev/null 2>&1 || true
  /bin/rm -rf -- "$test_dir"
  /bin/rm -f -- "$out_file"
}
trap cleanup EXIT

PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=update-termination \
PESTY_AUTOMATED_TEST_ID="$run_id" \
  "$executable" >"$out_file" 2>&1 &
test_pid=$!

timed_out=1
for _ in {1..150}; do
  state="$(ps -o state= -p "$test_pid" 2>/dev/null | tr -d ' ' || true)"
  if [[ -z "$state" || "$state" == Z* ]]; then
    timed_out=0
    break
  fi
  /bin/sleep 0.1
done

if [[ "$timed_out" -ne 0 ]]; then
  printf '%s\n' "Pesty did not finish update termination within 15 seconds" >&2
  exit 1
fi

if wait "$test_pid"; then
  exit_status=0
else
  exit_status=$?
fi
test_pid=""

if [[ "$exit_status" -ne 0 ]]; then
  printf '%s\n' "Pesty exited with status $exit_status" >&2
  sed -n '1,120p' "$out_file" >&2
  exit 1
fi

if ! /usr/bin/grep -q \
  'AUTOMATED_UPDATE_TERMINATION_RESULT {"success":true}' \
  "$out_file"; then
  printf '%s\n' "Pesty did not report a successful update termination" >&2
  sed -n '1,120p' "$out_file" >&2
  exit 1
fi

printf '%s\n' "Update termination regression passed"
