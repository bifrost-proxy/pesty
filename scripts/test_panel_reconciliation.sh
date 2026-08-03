#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary="${1:-.build/debug/Pesty}"
if [[ ! -x "$binary" ]]; then
  echo "Panel reconciliation test binary is missing: $binary" >&2
  exit 2
fi

test_dir="$(mktemp -d)"
cleanup() {
  defaults delete "$suite" >/dev/null 2>&1 || true
  find "$test_dir" -depth -delete
}
trap cleanup EXIT

run_id="panel-reconciliation-$(date +%s)-$$"
suite="com.bifrostproxy.pesty.$run_id"
output="$test_dir/output.log"

PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir/data" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=panel-reconciliation \
PESTY_AUTOMATED_TEST_ID="$run_id" \
  "$binary" >"$output"

result_line="$(sed -n '/^AUTOMATED_PANEL_RECONCILIATION_RESULT /p' "$output" | tail -1)"
if [[ -z "$result_line" ]]; then
  echo "Panel reconciliation test did not emit a result." >&2
  exit 1
fi
result_json="${result_line#AUTOMATED_PANEL_RECONCILIATION_RESULT }"
if [[ "$(jq -r '.success' <<<"$result_json")" != "true" ]]; then
  echo "$result_line"
  exit 1
fi

echo "$result_line"
