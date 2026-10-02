#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Mein Finanzplan"
BUNDLE_ID="de.weichert.meinfinanzplan"
ENTITLEMENTS="MeinFinanzplan.entitlements"
VERSION="$(cat VERSION | tr -d '[:space:]')"
BUILD_NUMBER="$(cat BUILD_NUMBER | tr -d '[:space:]')"
OUT_DIR="releases/v$VERSION"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"

echo "Version: $VERSION"
echo "Baue Universal-Release für Apple Silicon und Intel..."
swift build -c release --product MeinFinanzplan \
  --triple arm64-apple-macosx14.0 \
  --scratch-path .build-arm64
swift build -c release --product MeinFinanzplan \
  --triple x86_64-apple-macosx14.0 \
  --scratch-path .build-x86_64

ARM_BINARY=".build-arm64/arm64-apple-macosx/release/MeinFinanzplan"
INTEL_BINARY=".build-x86_64/x86_64-apple-macosx/release/MeinFinanzplan"
if [ ! -f "$ARM_BINARY" ] || [ ! -f "$INTEL_BINARY" ]; then
  echo "Mindestens ein Architektur-Binary wurde nicht gefunden." >&2
  exit 1
fi

echo "Baue App-Bundle..."
mkdir -p "$OUT_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "Resources/AppIcon-Dark.icns" "$APP_BUNDLE/Contents/Resources/AppIcon-Dark.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.finance</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 CreativTechnik</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Mein Finanzplan kann Buchungen und Wiederholungen optional in einem eigenen Kalender „Mein Finanzplan“ spiegeln. Dafür wird Kalenderzugriff benötigt.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo "Bereinige erweiterte Dateiattribute..."
xattr -cr "$APP_BUNDLE"

echo "Signiere App-Bundle (ad-hoc mit Hardened Runtime, nur lokal)..."
codesign --force --deep --options runtime --timestamp=none \
  --entitlements "$ENTITLEMENTS" --sign - "$APP_BUNDLE"

SIGNED_ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_BUNDLE" 2>&1 | sed -n '/<?xml/,$p')"
if ! printf '%s' "$SIGNED_ENTITLEMENTS" \
  | plutil -extract 'com\.apple\.security\.personal-information\.calendars' raw -o - - \
  | grep -qx 'true'; then
  echo "Kalender-Entitlement fehlt in der App-Signatur." >&2
  exit 1
fi

ARCHITECTURES="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"
if [[ "$ARCHITECTURES" != *"arm64"* ]] || [[ "$ARCHITECTURES" != *"x86_64"* ]]; then
  echo "Universal-Binary unvollständig: $ARCHITECTURES" >&2
  exit 1
fi

rm -rf "dist"
ln -s "releases/v$VERSION" "dist"

echo ""
echo "Fertig: $APP_BUNDLE"
echo "Zum Starten doppelklicken oder: open \"$APP_BUNDLE\""
