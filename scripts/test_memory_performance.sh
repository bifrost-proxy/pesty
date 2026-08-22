#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary="${1:-.build/release/Pesty}"
if [[ ! -x "$binary" ]]; then
  echo "Memory performance test binary is missing: $binary" >&2
  exit 2
fi

test_root="$(mktemp -d)"
cloud_dir="$test_root/cloud"
local_dir="$test_root/device"
suite="com.bifrostproxy.pesty.memory.$(date +%s).$$"
run_id="memory-$(date +%s)-$$"

cleanup() {
  defaults delete "$suite" >/dev/null 2>&1 || true
  find "$test_root" -depth -delete
}
trap cleanup EXIT

defaults write "$suite" iCloudSync -bool true
defaults write "$suite" historyLimit -int 3000
defaults write "$suite" historyLimitUnlimited -bool false

common_environment=(
  PESTY_AUTOMATED_TEST_DATA_DIR="$cloud_dir"
  PESTY_AUTOMATED_INCREMENTAL_SYNC=1
  PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR="$local_dir"
  PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite"
  PESTY_AUTOMATED_TEST_ID="$run_id"
)

seed_output="$test_root/seed.log"
set +e
env "${common_environment[@]}" \
  PESTY_AUTOMATED_UI_TEST=memory-seed \
  "$binary" >"$seed_output"
seed_exit_code=$?
set -e
seed_result="$(sed -n '/^AUTOMATED_MEMORY_SEED_RESULT /p' \
  "$seed_output" | tail -1)"
if [[ "$seed_exit_code" -ne 0 ]] \
  || [[ -z "$seed_result" ]] \
  || [[ "$(jq -r '.success' <<<"${seed_result#* }")" != "true" ]]; then
  echo "Memory seed failed." >&2
  sed -n '1,120p' "$seed_output" >&2
  exit 1
fi

measure_output="$test_root/measure.log"
set +e
env "${common_environment[@]}" \
  PESTY_AUTOMATED_UI_TEST=memory-measure \
  "$binary" >"$measure_output"
measure_exit_code=$?
set -e
measure_result="$(sed -n '/^AUTOMATED_MEMORY_PERFORMANCE_RESULT /p' \
  "$measure_output" | tail -1)"
if [[ -z "$measure_result" ]]; then
  echo "Memory measurement did not emit a result." >&2
  sed -n '1,160p' "$measure_output" >&2
  exit 1
fi

measure_json="${measure_result#AUTOMATED_MEMORY_PERFORMANCE_RESULT }"
if [[ "$measure_exit_code" -ne 0 ]] \
  || [[ "$(jq -r '.success' <<<"$measure_json")" != "true" ]]; then
  echo "$measure_result"
  echo "Memory performance limits failed." >&2
  exit 1
fi

fresh_output="$test_root/fresh.log"
set +e
env "${common_environment[@]}" \
  PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR="$test_root/fresh-device" \
  PESTY_AUTOMATED_UI_TEST=memory-fresh-sync \
  "$binary" >"$fresh_output"
fresh_exit_code=$?
set -e
fresh_result="$(sed -n '/^AUTOMATED_MEMORY_FRESH_SYNC_RESULT /p' \
  "$fresh_output" | tail -1)"
if [[ "$fresh_exit_code" -ne 0 ]] \
  || [[ -z "$fresh_result" ]] \
  || [[ "$(jq -r '.success' <<<"${fresh_result#* }")" != "true" ]]; then
  echo "${fresh_result:-Memory fresh-device sync emitted no result.}"
  echo "Fresh-device checkpoint memory limit failed." >&2
  exit 1
fi

state="$local_dir/sync-v2-local/state.json"
jq -e '
    (.historyVersions | keys | length) == (.snapshot.history | length)
    and all(.historyVersions | keys[]; test("^[0-9a-f]{64}$"))
  ' "$state" >/dev/null
text_bytes="$(jq '[.snapshot.history[].text // "" | utf8bytelength] | add' \
  "$state")"
state_bytes="$(stat -f '%z' "$state")"
if (( text_bytes < 45000000 )); then
  echo "Synthetic history is too small to represent the production workload." >&2
  exit 1
fi
if (( state_bytes > text_bytes * 5 / 4 )); then
  echo "Incremental state $state_bytes bytes duplicates too much of the $text_bytes-byte history." >&2
  exit 1
fi

echo "$seed_result"
echo "$measure_result"
echo "$fresh_result"
printf 'MEMORY_STATE_RESULT {"stateBytes":%s,"textBytes":%s,"historyVersionKeyBytes":%s}\n' \
  "$state_bytes" \
  "$text_bytes" \
  "$(jq '[.historyVersions | keys[] | utf8bytelength] | add' "$state")"
