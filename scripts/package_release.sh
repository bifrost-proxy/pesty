#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
APP="packaging/Pesty.app"
DMG="packaging/Pesty-$VERSION.dmg"

[ -d "$APP" ] || { echo "Missing $APP - run build_app.sh first"; exit 1; }

echo "==> Verifying ad-hoc signed app"
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE_INFO="$(codesign -dvvv "$APP" 2>&1)"
if ! grep -q "Signature=adhoc" <<< "$SIGNATURE_INFO"; then
  echo "Expected an ad-hoc signature on $APP"
  exit 1
fi

echo "==> Building DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Pesty.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pesty" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "==> Applying ad-hoc signature to DMG"
codesign --force --sign - "$DMG"
codesign --verify --verbose=2 "$DMG"
hdiutil verify "$DMG"

shasum -a 256 "$DMG"
echo "==> Done: $DMG"
