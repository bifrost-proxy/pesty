#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: generate_cask.sh VERSION SHA256 [OUTPUT]}"
SHA256="${2:?usage: generate_cask.sh VERSION SHA256 [OUTPUT]}"
OUTPUT="${3:-packaging/pesty.rb}"

case "$VERSION" in
  *[!0-9.]* | .* | *..* | *.)
    echo "VERSION must contain only dot-separated numbers: $VERSION"
    exit 1
    ;;
esac

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must be a stable semantic version: $VERSION"
  exit 1
fi
if ! [[ "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "SHA256 must be 64 lowercase hexadecimal characters"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
sed \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__SHA256__/$SHA256/g" \
  packaging/homebrew/pesty.rb.template > "$OUTPUT"

ruby -c "$OUTPUT"
echo "Generated $OUTPUT"
