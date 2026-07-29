#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary="${1:-.build/release/Pesty}"
maximum_rss_bytes="${PESTY_MAX_RSS_BYTES:-100000000}"
maximum_footprint_bytes="${PESTY_MAX_FOOTPRINT_BYTES:-100000000}"
include_images="${PESTY_PERFORMANCE_INCLUDE_IMAGES:-0}"

if [[ ! -x "$binary" ]]; then
  echo "Performance test binary is missing or not executable: $binary" >&2
  exit 2
fi

test_dir="$(mktemp -d)"
cleanup() {
  find "$test_dir" -depth -delete
}
trap cleanup EXIT

output_file="$test_dir/output.log"
time_file="$test_dir/time.log"
run_id="strip-$(date +%s)-$$"

set +e
env \
  PESTY_AUTOMATED_TEST_DATA_DIR="$test_dir/data" \
  PESTY_AUTOMATED_UI_TEST=performance \
  PESTY_AUTOMATED_TEST_ID="$run_id" \
  PESTY_PERFORMANCE_INCLUDE_IMAGES="$include_images" \
  /usr/bin/time -l "$binary" -historyLimit 5000 >"$output_file" 2>"$time_file"
app_exit_code=$?
set -e

result_line="$(sed -n '/^AUTOMATED_PERFORMANCE_TEST_RESULT /p' "$output_file" | tail -1)"
if [[ -z "$result_line" ]]; then
  echo "Performance test did not emit a result." >&2
  sed -n '1,160p' "$time_file" >&2
  exit 1
fi

result_json="${result_line#AUTOMATED_PERFORMANCE_TEST_RESULT }"
max_rss="$(awk '/maximum resident set size/ { print $1; exit }' "$time_file")"
peak_footprint="$(awk '/peak memory footprint/ { print $1; exit }' "$time_file")"

if [[ "$app_exit_code" -ne 0 ]] || [[ "$(jq -r '.success' <<<"$result_json")" != "true" ]]; then
  echo "$result_line"
  echo "Performance UI assertions failed." >&2
  exit 1
fi

if grep -q "behavior of the UICollectionViewFlowLayout is not defined" "$time_file"; then
  echo "$result_line"
  echo "NSCollectionViewFlowLayout reported an invalid item size." >&2
  exit 1
fi

if [[ -z "$max_rss" ]] || ! [[ "$max_rss" =~ ^[0-9]+$ ]]; then
  echo "Unable to read maximum resident set size from /usr/bin/time." >&2
  exit 1
fi

if (( max_rss > maximum_rss_bytes )); then
  echo "$result_line"
  echo "Maximum RSS $max_rss exceeds the $maximum_rss_bytes byte limit." >&2
  exit 1
fi

if [[ -z "$peak_footprint" ]] || ! [[ "$peak_footprint" =~ ^[0-9]+$ ]]; then
  echo "Unable to read peak memory footprint from /usr/bin/time." >&2
  exit 1
fi

if (( peak_footprint > maximum_footprint_bytes )); then
  echo "$result_line"
  echo "Peak footprint $peak_footprint exceeds the $maximum_footprint_bytes byte limit." >&2
  exit 1
fi

persisted_count="$(jq -r '.history | length' "$test_dir/data/store.json")"
if [[ "$persisted_count" != "1000" ]]; then
  echo "Persisted store contains $persisted_count items instead of 1000." >&2
  exit 1
fi

echo "$result_line"
echo "PERFORMANCE_MEMORY_RESULT {\"maximumRSSBytes\":$max_rss,\"peakFootprintBytes\":$peak_footprint,\"rssLimitBytes\":$maximum_rss_bytes,\"footprintLimitBytes\":$maximum_footprint_bytes,\"includesImages\":$include_images}"
