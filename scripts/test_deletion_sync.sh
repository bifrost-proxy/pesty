#!/usr/bin/env bash
set -euo pipefail

BINARY="${1:-.build/debug/Pesty}"
TEST_DIR="$(mktemp -d)"
DEFAULTS_SUITE="com.bifrostproxy.pesty.deletion-sync.$(date +%s).$$"
RUN_ID="deletion-sync-$(date +%s)-$$"

cleanup() {
  defaults delete "$DEFAULTS_SUITE" >/dev/null 2>&1 || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

for phase in \
  deletion-sync-seed \
  deletion-sync-restart-1 \
  deletion-sync-restart-2
do
  PESTY_AUTOMATED_TEST_DATA_DIR="$TEST_DIR" \
  PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$DEFAULTS_SUITE" \
  PESTY_AUTOMATED_UI_TEST="$phase" \
  PESTY_AUTOMATED_TEST_ID="$RUN_ID" \
    "$BINARY"
done
