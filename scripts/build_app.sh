#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
ARCHS="${ARCHS:-arm64 x86_64}"
APP="packaging/Pesty.app"

BUILD_ARGS=()
for arch in $ARCHS; do
  BUILD_ARGS+=(--arch "$arch")
done

echo "==> Building release binary ($ARCHS)"
swift build -c release "${BUILD_ARGS[@]}"

BIN="$(swift build -c release "${BUILD_ARGS[@]}" --show-bin-path)/Pesty"
echo "    binary: $BIN"

echo "==> Generating icon"
bash scripts/make_icon.sh >/dev/null

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pesty"
cp packaging/Pesty.icns "$APP/Contents/Resources/Pesty.icns"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    packaging/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Applying ad-hoc code signature"
codesign --force --sign - "$APP/Contents/MacOS/Pesty"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Built $APP"
/usr/bin/file "$APP/Contents/MacOS/Pesty"
echo "    version $VERSION ($BUILD)"
