#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Mein Finanzplan"
VERSION="$(cat VERSION | tr -d '[:space:]')"
OUT_DIR="releases/v$VERSION"
DMG_PATH="$OUT_DIR/$APP_NAME.dmg"
PKG_PATH="$OUT_DIR/$APP_NAME.pkg"
UPDATE_PKG_PATH="$OUT_DIR/$APP_NAME Update.pkg"
PACKAGE_NAME="Mein-Finanzplan-macOS-v$VERSION"
STAGING_DIR="$OUT_DIR/$PACKAGE_NAME"
ZIP_FILE="$PACKAGE_NAME.zip"
ZIP_PATH="$OUT_DIR/$ZIP_FILE"

if [ ! -f "$DMG_PATH" ] || [ ! -f "$PKG_PATH" ] || [ ! -f "$UPDATE_PKG_PATH" ]; then
  echo "DMG oder PKG fehlt. Erst ausführen: ./build-app.sh && ./build-dmg.sh && ./build-pkg.sh" >&2
  exit 1
fi

echo "Erstelle Weitergabe-Paket..."
rm -rf "$STAGING_DIR" "$ZIP_PATH"
mkdir -p "$STAGING_DIR"
cp "$DMG_PATH" "$STAGING_DIR/"
cp "$PKG_PATH" "$STAGING_DIR/"
cp "$UPDATE_PKG_PATH" "$STAGING_DIR/"
cp "distribution/INSTALLATION.txt" "$STAGING_DIR/INSTALLATION.txt"
cp "distribution/INSTALLIEREN.command" "$STAGING_DIR/INSTALLIEREN.command"
cp "distribution/DIAGNOSE.command" "$STAGING_DIR/DIAGNOSE.command"
chmod +x "$STAGING_DIR/INSTALLIEREN.command"
chmod +x "$STAGING_DIR/DIAGNOSE.command"

(
  cd "$STAGING_DIR"
  shasum -a 256 "$APP_NAME.dmg" "$APP_NAME.pkg" "$APP_NAME Update.pkg" > "SHA256-PRUEFSUMME.txt"
)

(
  cd "$OUT_DIR"
  COPYFILE_DISABLE=1 zip -r -X -q "$ZIP_FILE" "$PACKAGE_NAME"
)
rm -rf "$STAGING_DIR"

echo "Fertig: $ZIP_PATH"
