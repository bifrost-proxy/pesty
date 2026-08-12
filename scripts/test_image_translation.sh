#!/usr/bin/env bash
set -euo pipefail

BIN="${1:-.build/debug/Pesty}"
TEST_DIR="$(mktemp -d)"
RUN_ID="image-translation-$(date +%s)"
SUITE="com.bifrostproxy.pesty.image-translation.$RUN_ID"

cleanup() {
  defaults delete "$SUITE" >/dev/null 2>&1 || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

PESTY_AUTOMATED_TEST_DATA_DIR="$TEST_DIR" \
PESTY_AUTOMATED_TEST_DEFAULTS_SUITE="$SUITE" \
PESTY_AUTOMATED_UI_TEST=image-translation \
PESTY_AUTOMATED_TEST_ID="$RUN_ID" \
  "$BIN"
