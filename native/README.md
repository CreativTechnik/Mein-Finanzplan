# Mein Finanzplan - native macOS-App

Eigenständige SwiftUI/AppKit-Anwendung für macOS. Konten, Buchungen, Wiederholungen,
Budgets und Liquiditätsplanung laufen vollständig nativ und ohne Browser oder lokalen
Webserver.

Die Oberfläche verwendet das eigens entwickelte Farbsystem **Nordlicht Blau**:
Eisblau als ruhige Bühne, Porzellanweiß für Arbeitsflächen, Fjordblau für Interaktionen
und tiefes Tintenblau für Zahlen und Texte. Das zugehörige App-Icon liegt als skalierbarer
macOS-Ressourcensatz unter `Resources/`.

Seit Version 0.11.1 werden Diagrammdaten vorab aufbereitet, lange Listen verzögert
gerendert und Einzelbuchungen gezielt per Datenbank-ID geladen. Die Jahresansicht
reduziert unsichtbare Zwischenpunkte und erhöht die Detailstufe beim Zoomen wieder.
Beide App-Icons besitzen außerhalb ihrer abgerundeten Form echte Transparenz.

Seit Version 0.12.0 verwenden Übersicht und Statistik echte, navigierbare
Kalenderperioden (Tag, Woche, Monat, Quartal, 6 Monate, Jahr, freier Zeitraum) statt
rollierender Zeitfenster; das Übersichtsdiagramm zeigt dabei auch tatsächlich
gebuchte Vergangenheit an, und die „Demnächst“-Liste folgt demselben Zeitraum statt
einer festen Anzahl. Wiederkehrende Regeln können jetzt beliebig viele zeitlich
gestaffelte Betragsänderungen (Erhöhung/Senkung oder neuer Gesamtbetrag) sowie
flexible monatliche Zahlungstermine speichern: fester Kalendertag, ein
Datumsfenster (z. B. 15.–25., konservativ für die Liquiditätsplanung) oder ein
Wochentag vor einem Stichtag (z. B. letzter Mittwoch am/vor dem 28.) mit manuell
gepflegten Ausnahmeterminen für Feiertage.

## Aufbau

- `Sources/FinanceCore` - Datenmodell, SQLite-Persistenz, CSV-Import, Berichte und Liquiditäts-Engine.
- `Sources/MeinFinanzplan` - native Oberfläche und Anwendungszustand.
- `Sources/VerifyFinanceCore` - unabhängiges Prüfprogramm für die Fachlogik.
- `DESIGN.md` - Farb-, Typografie-, Layout- und Bewegungsregeln.
- `Resources/AppIcon.icns` und `Resources/AppIcon-Dark.icns` - eingebettete Icons für helles und dunkles Erscheinungsbild.

## Eigene Datenbank

Die App speichert ihre Daten unter `~/Library/Application Support/MeinFinanzplan/finanzplan.sqlite`.
Die Daten bleiben lokal auf dem Mac. Der Speicherort wird auch in der App unter
„Einstellungen“ angezeigt.

## Bauen und starten

Entwicklung (Fenster öffnet direkt aus dem Terminal):

```bash
swift run MeinFinanzplan
```

Fertiges, doppelklickbares App-Bundle:

```bash
./build-app.sh
open "dist/Mein Finanzplan.app"
```

Installations-DMG und PKG erzeugen:

```bash
./build-dmg.sh
./build-pkg.sh
```

Weitergabe-ZIP mit PKG für die normale Doppelklick-Installation, separatem
Update-only-PKG für bestehende Installationen, DMG, Anleitung, geprüftem
Fallback-Installer, technischer Ziel-Mac-Diagnose und SHA-256-Prüfsummen erzeugen:

```bash
./build-share-zip.sh
```

Den vollständigen Weitergabeweg inklusive künstlicher Download-Quarantäne und
App-Start in einer netzwerkgesperrten macOS-Sandbox prüfen:

```bash
./test-release-sandbox.sh
```

Der Release-Build ist ein Universal-Binary für Apple Silicon (`arm64`) und Intel
(`x86_64`) ab macOS 14. App und DMG werden ad-hoc signiert; das PKG bietet denselben
normalen Doppelklick-Installationsweg wie das bisherige Filelio-Paket. Ohne
Apple-Developer-ID kann Gatekeeper abhängig vom Übertragungsweg dennoch einen
Bestätigungsschritt oder den beigefügten Fallback-Installer verlangen.
Für eine ohne Sonderweg von Gatekeeper akzeptierte Verteilung wird weiterhin eine
Apple Developer ID samt Apple-Notarisierung benötigt.

Voraussetzung sind die Xcode Command Line Tools mit Swift 6, SwiftUI, Charts und
systemeigenem SQLite. Ein vollständiges Xcode ist für diesen Build nicht nötig.

## Business-Logik prüfen

Das unabhängige Prüfprogramm deckt Liquiditätsberechnung, Wiederholungsregeln,
Kontostände und lokale Datenbankänderungen ab:

```bash
swift run VerifyFinanceCore
```

Der aktuelle Umfang umfasst 79 Prüfungen, einschließlich aller Konto-Prognosereihen,
Spar- und Einnahmezielen, gespeicherten Konto- und Kategoriefarben, sicherer
Kontolöschung, atomarem Sicherungsimport, Rückfallebene und Schutz vor ungültigen
Importdateien. Zusätzlich werden Archivierung, Kategorie-Löschung, deutsche
CSV-Formate, Duplikatschutz und der zweiseitige PDF-Bericht geprüft. Seit Version
0.12.0 zusätzlich: Kalendergrenzen und -navigation für Monat/Quartal/Halbjahr/Jahr
und freien Zeitraum, mehrstufige Betragsänderungen mit Grenzdatum, Datumsfenster-
und Wochentag-vor-Stichtag-Termine samt Ausnahmeterminen, Sicherungs-Roundtrip
dieser neuen Felder sowie die historische Kontoverlaufs-Rekonstruktion.

© 2026 CreativTechnik
