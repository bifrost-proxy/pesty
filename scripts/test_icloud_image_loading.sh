#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary="${1:-.build/debug/Pesty}"
if [[ ! -x "$binary" ]]; then
  echo "iCloud image loading test binary is missing: $binary" >&2
  exit 2
fi

test_dir="$(mktemp -d)"
run_id="icloud-image-loading-$(date +%s)-$$"
suite="com.bifrostproxy.pesty.$run_id"
output="$test_dir/output.log"

cleanup() {
  defaults delete "$suite" >/dev/null 2>&1 || true
  find "$test_dir" -depth -delete
}
trap cleanup EXIT

set +e
PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir/data" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_IMAGE_DOWNLOAD_DELAY_MS=1200 \
PESTY_AUTOMATED_UI_TEST=preview \
PESTY_AUTOMATED_TEST_ID="$run_id" \
  "$binary" >"$output"
binary_status=$?
set -e

result_line="$(sed -n '/^AUTOMATED_PREVIEW_RESULT /p' "$output" | tail -1)"
if [[ -z "$result_line" ]]; then
  cat "$output" >&2
  echo "iCloud image loading test did not emit a result." >&2
  exit 1
fi
result_json="${result_line#AUTOMATED_PREVIEW_RESULT }"

if [[ "$binary_status" -ne 0 ]] \
    || [[ "$(jq -r '.success' <<<"$result_json")" != "true" ]] \
    || [[ "$(jq -r '.imageShowedICloudLoading' <<<"$result_json")" != "true" ]] \
    || [[ "$(jq -r '.imageDecoded' <<<"$result_json")" != "true" ]]; then
  echo "$result_line"
  echo "iCloud image loading UI assertions failed." >&2
  exit 1
fi

echo "$result_line"
