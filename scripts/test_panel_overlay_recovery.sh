#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary="${1:-.build/debug/Pesty}"

if [[ ! -x "$binary" ]]; then
  echo "Panel overlay recovery test binary is missing or not executable: $binary" >&2
  exit 2
fi

test_dir="$(mktemp -d)"
run_id="panel-overlay-$(date +%s)-$$"
suite="com.bifrostproxy.pesty.panel-overlay.$run_id"
cleanup() {
  defaults delete "$suite" >/dev/null 2>&1 || true
  find "$test_dir" -depth -delete
}
trap cleanup EXIT

output="$({
  PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
  PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
  PESTY_AUTOMATED_UI_TEST=panel-overlay-recovery \
  PESTY_AUTOMATED_TEST_ID="$run_id" \
    "$binary"
} 2>&1)"

result_line="$(sed -n '/^AUTOMATED_PANEL_OVERLAY_RECOVERY_RESULT /p' <<<"$output" | tail -1)"
if [[ -z "$result_line" ]]; then
  echo "$output" >&2
  echo "Panel overlay recovery test did not emit a result." >&2
  exit 1
fi

result_json="${result_line#AUTOMATED_PANEL_OVERLAY_RECOVERY_RESULT }"
if [[ "$(jq -r '.success' <<<"$result_json")" != "true" ]]; then
  echo "$result_line"
  echo "Panel overlay recovery assertions failed." >&2
  exit 1
fi

echo "$result_line"
