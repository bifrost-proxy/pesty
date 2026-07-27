#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
ARCHS="${ARCHS:-arm64 x86_64}"
APP="packaging/Pesty.app"

BUILD_ARGS=()
BUILD_ARCHS=()
for arch in $ARCHS; do
  BUILD_ARCHS+=("$arch")
  BUILD_ARGS+=(--arch "$arch")
done

echo "==> Building release binary ($ARCHS)"
XCBUILD="$(xcrun --find xcbuild 2>/dev/null || true)"
if [[ -n "$XCBUILD" && -x "$XCBUILD" ]]; then
  swift build -c release "${BUILD_ARGS[@]}"
  BIN="$(swift build -c release "${BUILD_ARGS[@]}" --show-bin-path)/Pesty"
else
  echo "    xcbuild unavailable; building each architecture with an explicit target"
  ARCH_BINARIES=()
  for arch in "${BUILD_ARCHS[@]}"; do
    SCRATCH_PATH=".build-release-$arch"
    swift build \
      -c release \
      --triple "$arch-apple-macosx14.0" \
      --scratch-path "$SCRATCH_PATH"
    ARCH_BINARIES+=("$SCRATCH_PATH/$arch-apple-macosx/release/Pesty")
  done

  UNIVERSAL_DIR=".build/pesty-universal/release"
  mkdir -p "$UNIVERSAL_DIR"
  BIN="$UNIVERSAL_DIR/Pesty"
  lipo -create "${ARCH_BINARIES[@]}" -output "$BIN"
fi
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
