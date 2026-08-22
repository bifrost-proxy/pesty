#!/bin/bash
set -euo pipefail

binary="${1:-.build/debug/Pesty}"
test_root="$(mktemp -d)"
cloud_dir="$test_root/cloud"
suite="com.bifrostproxy.pesty.incremental.$(date +%s)"
current_id="current-$(date +%s)"

cleanup() {
  defaults delete "$suite" >/dev/null 2>&1 || true
}
trap cleanup EXIT

defaults write "$suite" iCloudSync -bool true

"$binary" --verify-incremental-sync-compaction

# Publish four immutable incremental records from the first device.
PESTY_AUTOMATED_TEST_DATA_DIR="$cloud_dir" \
PESTY_AUTOMATED_INCREMENTAL_SYNC=1 \
PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR="$test_root/device-a" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=seed \
PESTY_AUTOMATED_TEST_ID="$current_id" \
  "$binary"

test ! -e "$cloud_dir/store.json"

# Existing 1.7.0-1.7.3 states used the complete clipboard content as each
# historyVersions key. Rewrite this isolated synthetic state into that legacy
# shape, then prove the next launch migrates every key to a fixed digest without
# losing history.
device_a_state="$test_root/device-a/sync-v2-local/state.json"
legacy_state="$test_root/legacy-state.json"
jq '
    (.historyVersions | to_entries | map(.value) | max) as $latest
    | .historyVersions = reduce .snapshot.history[] as $item
        ({}; .["txt:" + ($item.text // "")] = $latest)
  ' "$device_a_state" >"$legacy_state"
mv "$legacy_state" "$device_a_state"

PESTY_AUTOMATED_TEST_DATA_DIR="$cloud_dir" \
PESTY_AUTOMATED_INCREMENTAL_SYNC=1 \
PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR="$test_root/device-a" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=restart-1 \
PESTY_AUTOMATED_TEST_ID="$current_id" \
  "$binary"

jq -e '
    (.historyVersions | keys | length) == 4
    and all(.historyVersions | keys[]; test("^[0-9a-f]{64}$"))
    and ([.snapshot.history[].text // ""
        | select(startswith("pesty-auto-"))] | length) == 4
  ' "$device_a_state" >/dev/null

# A fresh device reconstructs the baseline from current checkpoints and event
# batches only. Legacy monolithic stores are intentionally unsupported.
PESTY_AUTOMATED_TEST_DATA_DIR="$cloud_dir" \
PESTY_AUTOMATED_INCREMENTAL_SYNC=1 \
PESTY_AUTOMATED_INCREMENTAL_LOCAL_DIR="$test_root/device-b" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$suite" \
PESTY_AUTOMATED_UI_TEST=restart-1 \
PESTY_AUTOMATED_TEST_ID="$current_id" \
  "$binary"

state="$test_root/device-b/sync-v2-local/state.json"
jq -e --arg current "pesty-auto-$current_id-" '
    [.snapshot.history[].text // ""] as $texts
    | ([$texts[] | select(startswith($current))] | length) == 4
  ' "$state" >/dev/null

largest_batch="$(find "$cloud_dir/sync-v2/batches" -type f -name '*.json' \
  -exec stat -f '%z' {} \; | sort -nr | head -1)"
test "$largest_batch" -lt 300000

printf 'INCREMENTAL_SYNC_RESULT {"success":true,"largestBatchBytes":%s,"historyCount":4}\n' \
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
