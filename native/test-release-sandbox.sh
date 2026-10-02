#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
ZIP_PATH="releases/v$VERSION_VALUE/Mein-Finanzplan-macOS-v$VERSION_VALUE.zip"
TEST_DIRECTORY="$(mktemp -d /tmp/mein-finanzplan-sandbox.XXXXXX)"
UNPACKED="$TEST_DIRECTORY/Mein-Finanzplan-macOS-v$VERSION_VALUE"
MOUNT_DIRECTORY="$TEST_DIRECTORY/mount"
PKG_EXPANDED="$TEST_DIRECTORY/pkg-expanded"
PKG_APP="$PKG_EXPANDED/Payload/Mein Finanzplan.app"
UPDATE_PKG_EXPANDED="$TEST_DIRECTORY/update-pkg-expanded"
UPDATE_PKG_APP="$UPDATE_PKG_EXPANDED/Payload/Applications/Mein Finanzplan.app"
QUARANTINED_APP="$TEST_DIRECTORY/Quarantaene/Mein Finanzplan.app"
INSTALLED_APP="$TEST_DIRECTORY/Applications/Mein Finanzplan.app"
SANDBOX_PROFILE="$TEST_DIRECTORY/no-network.sb"
LOG_FILE="$TEST_DIRECTORY/start.log"

check_calendar_entitlement() {
  local app_path="$1"
  local signed_entitlements
  signed_entitlements="$(codesign -d --entitlements :- "$app_path" 2>&1 | sed -n '/<?xml/,$p')"
  if ! printf '%s' "$signed_entitlements" \
    | plutil -extract 'com\.apple\.security\.personal-information\.calendars' raw -o - - \
    | grep -qx 'true'; then
    printf 'FEHLER: Kalender-Entitlement fehlt in %s.\n' "$app_path" >&2
    exit 1
  fi
}

mkdir -p "$MOUNT_DIRECTORY"
unzip -q "$ZIP_PATH" -d "$TEST_DIRECTORY"
"$UNPACKED/INSTALLIEREN.command" --check

(
  cd "$UNPACKED"
  shasum -a 256 -c "SHA256-PRUEFSUMME.txt"
)

pkgutil --expand-full "$UNPACKED/Mein Finanzplan.pkg" "$PKG_EXPANDED"
[ -d "$PKG_APP" ] || {
  printf 'FEHLER: Im PKG fehlt Mein Finanzplan.app.\n' >&2
  exit 1
}
codesign --verify --deep --strict "$PKG_APP"
check_calendar_entitlement "$PKG_APP"
PKG_ARCHITECTURES="$(lipo -archs "$PKG_APP/Contents/MacOS/Mein Finanzplan")"
[[ "$PKG_ARCHITECTURES" == *arm64* ]] || {
  printf 'FEHLER: Im PKG fehlt die Apple-Silicon-Architektur.\n' >&2
  exit 1
}
[[ "$PKG_ARCHITECTURES" == *x86_64* ]] || {
  printf 'FEHLER: Im PKG fehlt die Intel-Architektur.\n' >&2
  exit 1
}
printf 'PKG-Inhalt erfolgreich geprüft (%s).\n' "$PKG_ARCHITECTURES"

pkgutil --expand-full "$UNPACKED/Mein Finanzplan Update.pkg" "$UPDATE_PKG_EXPANDED"
[ -d "$UPDATE_PKG_APP" ] || {
  printf 'FEHLER: Im Update-PKG fehlt Mein Finanzplan.app.\n' >&2
  exit 1
}
codesign --verify --deep --strict "$UPDATE_PKG_APP"
check_calendar_entitlement "$UPDATE_PKG_APP"
if ! rg -q '<update-bundle>' "$UPDATE_PKG_EXPANDED/PackageInfo"; then
  printf 'FEHLER: Das Update-PKG ist nicht als Update-only konfiguriert.\n' >&2
  exit 1
fi
printf 'Update-only-PKG erfolgreich geprüft.\n'

xattr -w com.apple.quarantine '0081;00000000;Sandbox-Test;' "$UNPACKED/Mein Finanzplan.dmg"
hdiutil attach "$UNPACKED/Mein Finanzplan.dmg" -nobrowse -readonly -mountpoint "$MOUNT_DIRECTORY" -quiet
mkdir -p "$TEST_DIRECTORY/Quarantaene"
ditto "$MOUNT_DIRECTORY/Mein Finanzplan.app" "$QUARANTINED_APP"
hdiutil detach "$MOUNT_DIRECTORY" -quiet

xattr -w com.apple.quarantine '0081;00000000;Sandbox-Test;' "$QUARANTINED_APP"
if spctl --assess --type execute "$QUARANTINED_APP" >/dev/null 2>&1; then
  printf 'FEHLER: Gatekeeper hat die absichtlich quarantänisierte Ad-hoc-App unerwartet akzeptiert.\n' >&2
  exit 1
else
  printf 'Gatekeeper-Blockade reproduziert.\n'
fi

bash "$UNPACKED/INSTALLIEREN.command" --install-only "$TEST_DIRECTORY/Applications"
if xattr -p com.apple.quarantine "$INSTALLED_APP" >/dev/null 2>&1; then
  printf 'FEHLER: Der Installer hat das Quarantaene-Merkmal nicht entfernt.\n' >&2
  exit 1
fi
codesign --verify --deep --strict "$INSTALLED_APP"

printf '(version 1)\n(allow default)\n(deny network*)\n' > "$SANDBOX_PROFILE"
sandbox-exec -f "$SANDBOX_PROFILE" "$INSTALLED_APP/Contents/MacOS/Mein Finanzplan" > "$LOG_FILE" 2>&1 &
APP_PROCESS_ID=$!
sleep 12
if ! kill -0 "$APP_PROCESS_ID" 2>/dev/null; then
  printf 'FEHLER: Die App blieb in der Sandbox nicht aktiv.\n' >&2
  sed -n '1,160p' "$LOG_FILE" >&2
  exit 1
fi

CPU_VALUE="$(ps -p "$APP_PROCESS_ID" -o %cpu= | tr -d ' ')"
MEMORY_VALUE="$(ps -p "$APP_PROCESS_ID" -o rss= | tr -d ' ')"
kill "$APP_PROCESS_ID"
wait "$APP_PROCESS_ID" 2>/dev/null || true

printf 'Sandbox-Start erfolgreich (Netzwerk gesperrt). CPU: %s %%, RSS: %s KB.\n' "$CPU_VALUE" "$MEMORY_VALUE"
printf 'Testartefakte: %s\n' "$TEST_DIRECTORY"
