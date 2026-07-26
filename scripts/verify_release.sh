#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: verify_release.sh VERSION [DMG]}"
DMG="${2:-packaging/Pesty-$VERSION.dmg}"
EXPECTED_ARCHS="${EXPECTED_ARCHS:-arm64 x86_64}"

[ -f "$DMG" ] || { echo "Missing release image: $DMG"; exit 1; }
hdiutil verify "$DMG"
codesign --verify --verbose=2 "$DMG"

MOUNT_ROOT="$(mktemp -d)"
MOUNT_POINT="$MOUNT_ROOT/Pesty"
mkdir -p "$MOUNT_POINT"
cleanup() {
  hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rm -rf "$MOUNT_ROOT"
}
trap cleanup EXIT

hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" -quiet
APP="$MOUNT_POINT/Pesty.app"
BIN="$APP/Contents/MacOS/Pesty"
PLIST="$APP/Contents/Info.plist"

[ -d "$APP" ] || { echo "Pesty.app is missing from $DMG"; exit 1; }
[ -x "$BIN" ] || { echo "Pesty executable is missing from $DMG"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE_INFO="$(codesign -dvvv "$APP" 2>&1)"
grep -q "Signature=adhoc" <<< "$SIGNATURE_INFO"

ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")"
[ "$ACTUAL_VERSION" = "$VERSION" ] || {
  echo "Expected version $VERSION, found $ACTUAL_VERSION"
  exit 1
}

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")"
[ "$BUNDLE_ID" = "com.bifrostproxy.pesty" ] || {
  echo "Unexpected bundle identifier: $BUNDLE_ID"
  exit 1
}

ARCHS="$(lipo -archs "$BIN")"
for expected_arch in $EXPECTED_ARCHS; do
  case " $ARCHS " in
    *" $expected_arch "*) ;;
    *) echo "$expected_arch architecture is missing: $ARCHS"; exit 1 ;;
  esac
done

echo "Verified Pesty $VERSION ($BUNDLE_ID; $ARCHS; ad-hoc signed)"
