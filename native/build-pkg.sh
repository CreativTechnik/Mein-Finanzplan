#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Mein Finanzplan"
BUNDLE_ID="de.weichert.meinfinanzplan"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(tr -d '[:space:]' < BUILD_NUMBER)"
OUT_DIR="releases/v$VERSION"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
PKG_PATH="$OUT_DIR/$APP_NAME.pkg"
UPDATE_PKG_PATH="$OUT_DIR/$APP_NAME Update.pkg"
UPDATE_ROOT="$OUT_DIR/.pkg-update-root"
COMPONENT_PLIST="$OUT_DIR/.pkg-update-components.plist"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "App-Bundle fehlt. Erst ausführen: ./build-app.sh" >&2
  exit 1
fi

echo "Baue PKG-Installer für Version $VERSION..."
COPYFILE_DISABLE=1 pkgbuild \
  --component "$APP_BUNDLE" \
  --install-location /Applications \
  --identifier "$BUNDLE_ID.installer" \
  --version "$BUILD_NUMBER" \
  "$PKG_PATH"

pkgutil --check-signature "$PKG_PATH" || true

echo "Baue Update-only-PKG für vorhandene Installationen..."
rm -rf "$UPDATE_ROOT" "$COMPONENT_PLIST" "$UPDATE_PKG_PATH"
mkdir -p "$UPDATE_ROOT/Applications"
ditto --norsrc "$APP_BUNDLE" "$UPDATE_ROOT/Applications/$APP_NAME.app"
pkgbuild --analyze --root "$UPDATE_ROOT" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable true" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsVersionChecked true" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleHasStrictIdentifier true" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleOverwriteAction update" "$COMPONENT_PLIST"

COPYFILE_DISABLE=1 pkgbuild \
  --root "$UPDATE_ROOT" \
  --component-plist "$COMPONENT_PLIST" \
  --install-location / \
  --identifier "$BUNDLE_ID.installer" \
  --version "$BUILD_NUMBER" \
  "$UPDATE_PKG_PATH"

pkgutil --check-signature "$UPDATE_PKG_PATH" || true
rm -rf "$UPDATE_ROOT" "$COMPONENT_PLIST"

echo "Fertig: $PKG_PATH"
echo "Fertig: $UPDATE_PKG_PATH"
