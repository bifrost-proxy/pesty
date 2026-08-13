#!/bin/bash
set -euo pipefail

binary="${1:-.build/debug/Pesty}"
test_dir="$(mktemp -d)"
run_id="icloud-store-$(date +%s)"
suite="com.bifrostproxy.pesty.icloud-store.$run_id"

cleanup() {
  defaults delete "$suite" >/dev/null 2>&1 || true
}
trap cleanup EXIT

defaults write "$suite" iCloudSync -bool true

seed_output="$({
  PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
  PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
  PESTY_AUTOMATED_UI_TEST=seed \
  PESTY_AUTOMATED_TEST_ID="$run_id" \
    "$binary"
} 2>&1)"
printf '%s\n' "$seed_output"
printf '%s\n' "$seed_output" \
  | grep 'AUTOMATED_UI_TEST_RESULT' \
  | sed 's/^AUTOMATED_UI_TEST_RESULT //' \
  | jq -e '.success == true and .persistedMatches == 4' >/dev/null

loading_output="$({
  PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir" \
  PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
  PESTY_AUTOMATED_STORE_DOWNLOAD_DELAY_MS=900 \
  PESTY_AUTOMATED_UI_TEST=icloud-store-loading \
  PESTY_AUTOMATED_TEST_ID="$run_id" \
    "$binary"
} 2>&1)"
printf '%s\n' "$loading_output"
printf '%s\n' "$loading_output" \
  | grep 'AUTOMATED_ICLOUD_STORE_LOADING_RESULT' \
  | sed 's/^AUTOMATED_ICLOUD_STORE_LOADING_RESULT //' \
  | jq -e '
      .success == true
      and .panelResponsiveWhileDownloading == true
      and .loadingStateRendered == true
      and .historyEmptyWhileDownloading == true
      and .recoveredAutomatically == true
      and .concurrentItemPreserved == true
      and .persistedMatches == 4
      and .historyMatches == 4
    ' >/dev/null
