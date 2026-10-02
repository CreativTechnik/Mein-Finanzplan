#!/bin/bash
set -euo pipefail

PACKAGE_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
DISK_IMAGE="$PACKAGE_DIRECTORY/Mein Finanzplan.dmg"
CHECKSUM_FILE="$PACKAGE_DIRECTORY/SHA256-PRUEFSUMME.txt"
MODE="${1:-}"
INSTALL_ONLY=false
USER_APPLICATIONS="$HOME/Applications"

fail() {
  printf '\nInstallation abgebrochen: %s\n' "$1" >&2
  printf 'Drücke Enter, um dieses Fenster zu schließen.\n'
  read -r _
  exit 1
}

[ -f "$DISK_IMAGE" ] || fail 'Mein Finanzplan.dmg wurde nicht neben dem Installer gefunden.'
[ -f "$CHECKSUM_FILE" ] || fail 'SHA256-PRUEFSUMME.txt fehlt.'

EXPECTED_CHECKSUM="$(awk 'NR == 1 { print $1 }' "$CHECKSUM_FILE")"
ACTUAL_CHECKSUM="$(shasum -a 256 "$DISK_IMAGE" | awk '{ print $1 }')"
[ -n "$EXPECTED_CHECKSUM" ] || fail 'Die gespeicherte Prüfsumme ist leer.'
[ "$EXPECTED_CHECKSUM" = "$ACTUAL_CHECKSUM" ] || fail 'Die DMG-Prüfsumme stimmt nicht. Bitte das Paket neu übertragen.'

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 14 ] || fail 'Diese Version benötigt macOS 14 Sonoma oder neuer.'

MOUNT_DIRECTORY="$(mktemp -d /tmp/mein-finanzplan-install.XXXXXX)"
cleanup() {
  hdiutil detach "$MOUNT_DIRECTORY" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIRECTORY" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DISK_IMAGE" -nobrowse -readonly -mountpoint "$MOUNT_DIRECTORY" -quiet || fail 'Das Disk-Image konnte nicht geöffnet werden.'
SOURCE_APP="$MOUNT_DIRECTORY/Mein Finanzplan.app"
[ -d "$SOURCE_APP" ] || fail 'Die App fehlt im Disk-Image.'
codesign --verify --deep --strict "$SOURCE_APP" >/dev/null 2>&1 || fail 'Die Codesignatur der App ist ungültig.'

ARCHITECTURES="$(lipo -archs "$SOURCE_APP/Contents/MacOS/Mein Finanzplan")"
[[ "$ARCHITECTURES" == *arm64* ]] || fail 'Die Apple-Silicon-Architektur fehlt.'
[[ "$ARCHITECTURES" == *x86_64* ]] || fail 'Die Intel-Architektur fehlt.'

if [ "$MODE" = "--check" ]; then
  printf 'Paketprüfung erfolgreich. Prüfsumme, Signatur und beide Architekturen sind in Ordnung.\n'
  exit 0
fi

if [ "$MODE" = "--install-only" ]; then
  TEST_DESTINATION="${2:-}"
  case "$TEST_DESTINATION" in
    /tmp/*) USER_APPLICATIONS="$TEST_DESTINATION"; INSTALL_ONLY=true ;;
    *) fail 'Der interne Test-Zielordner muss unter /tmp liegen.' ;;
  esac
fi

TARGET_APP="$USER_APPLICATIONS/Mein Finanzplan.app"
mkdir -p "$USER_APPLICATIONS"

if [ -e "$TARGET_APP" ]; then
  BACKUP_STAMP="$(date '+%Y-%m-%d %H-%M-%S')"
  BACKUP_APP="$USER_APPLICATIONS/Mein Finanzplan vorher $BACKUP_STAMP.app"
  mv "$TARGET_APP" "$BACKUP_APP" || fail 'Die vorhandene App konnte nicht gesichert werden.'
  printf 'Vorhandene Version gesichert: %s\n' "$BACKUP_APP"
fi

ditto "$SOURCE_APP" "$TARGET_APP" || fail 'Die App konnte nicht kopiert werden.'
xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
codesign --verify --deep --strict "$TARGET_APP" >/dev/null 2>&1 || fail 'Die installierte App hat die Signaturprüfung nicht bestanden.'

printf '\nMein Finanzplan wurde installiert.\n'
printf 'Speicherort: %s\n' "$TARGET_APP"

if [ "$INSTALL_ONLY" = true ]; then
  printf 'Installationsprüfung ohne automatischen Start abgeschlossen.\n'
  exit 0
fi

START_LOG_DIRECTORY="$HOME/Library/Logs"
START_LOG="$START_LOG_DIRECTORY/Mein Finanzplan Start.log"
mkdir -p "$START_LOG_DIRECTORY"

open "$TARGET_APP" >/dev/null 2>&1 || true
sleep 4

if ! pgrep -f "$TARGET_APP/Contents/MacOS/Mein Finanzplan" >/dev/null 2>&1; then
  printf 'Der Finder-Start war nicht erfolgreich. Versuche den direkten Start ...\n'
  "$TARGET_APP/Contents/MacOS/Mein Finanzplan" > "$START_LOG" 2>&1 &
  sleep 4
fi

if pgrep -f "$TARGET_APP/Contents/MacOS/Mein Finanzplan" >/dev/null 2>&1; then
  printf 'Start erfolgreich.\n'
else
  fail "Die App wurde installiert, beendet sich aber beim Start. Das Startprotokoll liegt unter: $START_LOG"
fi
