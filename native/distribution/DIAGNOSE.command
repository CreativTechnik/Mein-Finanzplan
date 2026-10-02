#!/bin/bash
set -u

PACKAGE_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
DISK_IMAGE="$PACKAGE_DIRECTORY/Mein Finanzplan.dmg"
CHECKSUM_FILE="$PACKAGE_DIRECTORY/SHA256-PRUEFSUMME.txt"
REPORT="$PACKAGE_DIRECTORY/DIAGNOSE-ERGEBNIS.txt"

exec > >(tee "$REPORT") 2>&1

printf 'MEIN FINANZPLAN - TECHNISCHE DIAGNOSE\n'
printf 'Erstellt: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf 'macOS: '; sw_vers -productVersion 2>/dev/null || printf 'unbekannt\n'
printf 'Build: '; sw_vers -buildVersion 2>/dev/null || printf 'unbekannt\n'
printf 'Prozessor: '; uname -m
printf 'Benutzer ist Administrator: '
if groups "$(id -un)" | grep -q '\badmin\b'; then printf 'ja\n'; else printf 'nein\n'; fi

printf '\nPAKETDATEIEN\n'
for item in "$DISK_IMAGE" "$CHECKSUM_FILE"; do
  if [ -e "$item" ]; then printf 'vorhanden: %s\n' "$(basename "$item")"; else printf 'FEHLT: %s\n' "$(basename "$item")"; fi
done

if [ ! -f "$DISK_IMAGE" ] || [ ! -f "$CHECKSUM_FILE" ]; then
  printf '\nErgebnis: Das Weitergabe-Paket ist unvollstaendig. Bitte die gesamte ZIP-Datei erneut uebertragen.\n'
  exit 1
fi

EXPECTED_CHECKSUM="$(awk 'NR == 1 { print $1 }' "$CHECKSUM_FILE")"
ACTUAL_CHECKSUM="$(shasum -a 256 "$DISK_IMAGE" | awk '{ print $1 }')"
printf '\nPRUEFSUMME\nErwartet: %s\nTatsaechlich: %s\n' "$EXPECTED_CHECKSUM" "$ACTUAL_CHECKSUM"
if [ "$EXPECTED_CHECKSUM" = "$ACTUAL_CHECKSUM" ]; then printf 'Ergebnis: korrekt\n'; else printf 'Ergebnis: FEHLER - Datei wurde veraendert oder unvollstaendig uebertragen.\n'; exit 1; fi

printf '\nQUARANTAENE DER DMG\n'
xattr -p com.apple.quarantine "$DISK_IMAGE" 2>/dev/null || printf 'kein Quarantaene-Merkmal\n'

MOUNT_DIRECTORY="$(mktemp -d /tmp/mein-finanzplan-diagnose.XXXXXX)"
cleanup() {
  hdiutil detach "$MOUNT_DIRECTORY" -quiet >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! hdiutil attach "$DISK_IMAGE" -nobrowse -readonly -mountpoint "$MOUNT_DIRECTORY" -quiet; then
  printf '\nErgebnis: FEHLER - Das Disk-Image kann nicht eingebunden werden.\n'
  exit 1
fi

SOURCE_APP="$MOUNT_DIRECTORY/Mein Finanzplan.app"
BINARY="$SOURCE_APP/Contents/MacOS/Mein Finanzplan"
printf '\nAPP IM DISK-IMAGE\n'
if [ ! -x "$BINARY" ]; then printf 'Ergebnis: FEHLER - Programmdatei fehlt oder ist nicht ausfuehrbar.\n'; exit 1; fi
printf 'Architekturen: '; lipo -archs "$BINARY" 2>&1 || file "$BINARY"
printf 'Mindest-macOS: '; defaults read "$SOURCE_APP/Contents/Info" LSMinimumSystemVersion 2>/dev/null || printf 'unbekannt\n'
printf 'Codesignatur: '
if codesign --verify --deep --strict "$SOURCE_APP" 2>/dev/null; then printf 'technisch gueltig\n'; else printf 'FEHLER\n'; fi
printf 'Gatekeeper: '
spctl --assess --type execute --verbose=4 "$SOURCE_APP" 2>&1 || true

printf '\nAUSWERTUNG\n'
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt 14 ]; then
  printf 'BLOCKER: Dieser Mac verwendet macOS %s; die App benoetigt macOS 14 oder neuer.\n' "$MACOS_MAJOR"
else
  printf 'macOS-Version und Prozessorarchitektur sind grundsaetzlich kompatibel.\n'
  printf 'Eine Gatekeeper-Ablehnung ist bei dieser nicht notarisierten Testversion zu erwarten.\n'
  printf 'Fuehre INSTALLIEREN.command wie in INSTALLATION.txt beschrieben ueber Terminal aus.\n'
fi
printf '\nDiagnose gespeichert unter:\n%s\n' "$REPORT"
