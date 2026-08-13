#!/bin/bash
set -euo pipefail

binary="${1:-.build/debug/Pesty}"
test_root="$(mktemp -d)"
cloud_dir="$test_root/cloud"
suite="com.bifrostproxy.pesty.incremental.$(date +%s)"
legacy_id="legacy-$(date +%s)"
current_id="current-$(date +%s)"

cleanup() {
  defaults delete "$suite" >/dev/null 2>&1 || true
}
trap cleanup EXIT

defaults write "$suite" iCloudSync -bool true

"$binary" --verify-incremental-sync-compaction

# Produce the legacy monolith with the previous storage path.
PESTY_AUTOMATED_TEST_DATA_DIR="$cloud_dir" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=seed \
PESTY_AUTOMATED_TEST_ID="$legacy_id" \
  "$binary"

test -s "$cloud_dir/store.json"

# Start v2 with no local history. The legacy read is intentionally delayed
# while four new clips are captured and synchronized through v2.
PESTY_AUTOMATED_TEST_DATA_DIR="$cloud_dir" \
PESTY_AUTOMATED_INCREMENTAL_SYNC=1 \
PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR="$test_root/device-a" \
PESTY_AUTOMATED_STORE_DOWNLOAD_DELAY_MS=2000 \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=seed \
PESTY_AUTOMATED_TEST_ID="$current_id" \
  "$binary"

test ! -e "$cloud_dir/store.json"
test "$(find "$cloud_dir/sync-v2/migration" -type f -name '*.json' | wc -l | tr -d ' ')" = 1

# A fresh device has no shared metadata cache. It must reconstruct both the
# migrated legacy records and the concurrent records from incremental batches.
PESTY_AUTOMATED_TEST_DATA_DIR="$cloud_dir" \
PESTY_AUTOMATED_INCREMENTAL_SYNC=1 \
PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR="$test_root/device-b" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=restart-1 \
PESTY_AUTOMATED_TEST_ID="$current_id" \
  "$binary"

state="$test_root/device-b/sync-v2-local/state.json"
jq -e --arg legacy "pesty-auto-$legacy_id-" \
  --arg current "pesty-auto-$current_id-" '
    [.snapshot.history[].text // ""] as $texts
    | ([$texts[] | select(startswith($legacy))] | length) == 4
    and ([$texts[] | select(startswith($current))] | length) == 4
  ' "$state" >/dev/null

largest_batch="$(find "$cloud_dir/sync-v2/batches" -type f -name '*.json' \
  -exec stat -f '%z' {} \; | sort -nr | head -1)"
test "$largest_batch" -lt 300000

printf 'INCREMENTAL_SYNC_RESULT {"success":true,"largestBatchBytes":%s,"historyCount":8}\n' \
  "$largest_batch"

# Tombstones must cross device boundaries and reject stale copies. The third
# device also proves that a genuinely new copy after deletion remains allowed.
deletion_cloud="$test_root/deletion-cloud"
deletion_id="incremental-delete-$(date +%s)"
for phase in deletion-sync-seed deletion-sync-restart-1 deletion-sync-restart-2; do
  PESTY_AUTOMATED_TEST_DATA_DIR="$deletion_cloud" \
  PESTY_AUTOMATED_INCREMENTAL_SYNC=1 \
  PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR="$test_root/$phase" \
  PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
  PESTY_AUTOMATED_UI_TEST="$phase" \
  PESTY_AUTOMATED_TEST_ID="$deletion_id" \
    "$binary"
done

printf 'INCREMENTAL_DELETION_RESULT {"success":true,"devices":3}\n'
