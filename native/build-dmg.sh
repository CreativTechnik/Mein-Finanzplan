#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Mein Finanzplan"
VERSION="$(cat VERSION | tr -d '[:space:]')"
OUT_DIR="releases/v$VERSION"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
DMG_PATH="$OUT_DIR/$APP_NAME.dmg"
STAGING_DIR="$OUT_DIR/.dmg-staging"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "App-Bundle fehlt. Erst ausführen: ./build-app.sh" >&2
  exit 1
fi

echo "Baue DMG für Version $VERSION..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto --norsrc "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO -fs HFS+ "$DMG_PATH"
codesign --force --sign - "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo ""
echo "Fertig: $DMG_PATH"
