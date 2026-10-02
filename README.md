<div align="center">
  <img src="native/Resources/AppIcon-Master.png" width="168" alt="Mein Finanzplan App-Icon">
  <h1>Mein Finanzplan</h1>
  <p><strong>Lokale Haushalts- und Liquiditätsplanung für macOS.</strong></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&amp;logoColor=white" alt="macOS 14 oder neuer">
    <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
    <img src="https://img.shields.io/badge/Datenschutz-lokal-1769AA" alt="Daten bleiben lokal">
    <img src="https://img.shields.io/badge/Version-0.15.2-1572A1" alt="Version 0.15.2">
  </p>
</div>

**Mein Finanzplan** beantwortet eine praktische Frage: Wie viel Geld ist heute wirklich frei verfügbar, wenn alle bekannten Zahlungen bis zur nächsten verlässlichen Einnahme und der gewünschte Mindestpuffer geschützt bleiben?

Die App arbeitet vollständig lokal. Es gibt keine Cloud, kein Benutzerkonto, kein Tracking und keine automatische Bankverbindung.

> [!IMPORTANT]
> Dieses Repository enthält zwei getrennte Anwendungen mit eigenen Datenbanken. Die native macOS-App ist der empfohlene Produktpfad; die Browser-Variante ist eine eigenständige lokale Alternative. Datenbanken sind nicht direkt austauschbar.

## Funktionsumfang

- Dashboard mit frei verfügbarem Betrag, Wochenbedarf und 90-Tage-Vorschau
- mehrere Konten mit Ist-Saldo, Plan-Saldo und individuellem Mindestpuffer
- Einnahmen, Ausgaben und vermögensneutrale Umbuchungen
- geplante, gebuchte und stornierte Buchungen
- monatliche, wöchentliche, jährliche und frei definierte Wiederholungen
- Kategorien, Unterkategorien und Monatsbudgets mit Plan-Ist-Vergleich
- Zeitachse, Statistiken und Warnungen bei Puffer-Unterschreitungen
- CSV-Import mit Vorschau und Erkennung sicherer oder möglicher Duplikate
- lokale Belege an Buchungen: PDF, JPEG, PNG, HEIC und TIFF
- Menüleisten-Zusammenfassung mit Privatsphäre im gesperrten Zustand
- JSON-Sicherung und Wiederherstellung
- heller und dunkler Modus sowie reduzierte Bewegung

## Varianten

| Variante | Status | Technik | Datenhaltung |
|---|---|---|---|
| Native macOS-App | empfohlen | SwiftUI, AppKit, Apple Charts | lokale SQLite-Datenbank |
| Lokale Browser-App | ergänzend | React, TypeScript, Fastify | separate lokale SQLite-Datenbank |

## Native macOS-App starten

Voraussetzungen:

- macOS 14 oder neuer
- Swift 6.2 oder neuer
- Apple Command Line Tools beziehungsweise Xcode

```bash
cd native
swift build
swift run MeinFinanzplan
```

Ein lokales App-Bundle erzeugen:

```bash
cd native
./build-app.sh
open "dist/Mein Finanzplan.app"
```

Die App wird lokal ad-hoc signiert. Für eine öffentliche Verteilung ohne Gatekeeper-Warnung fehlen derzeit Apple Developer ID und Notarisierung.

Weitere technische Einzelheiten stehen in [`native/README.md`](native/README.md).

## Browser-Variante starten

Voraussetzungen:

- Node.js 22.13 oder neuer
- npm

```bash
npm install
npm run build
npm start
```

Anschließend ist die Anwendung unter [`http://127.0.0.1:4178`](http://127.0.0.1:4178) erreichbar. Der Server bindet standardmäßig ausschließlich an den eigenen Mac.

Für die Entwicklung:

```bash
npm run dev
```

### Bewusster Zugriff im Heimnetz

```bash
HOST=0.0.0.0 npm start
```

> [!WARNING]
> Die Browser-App besitzt kein Login. Den Netzwerkmodus nur kurzfristig in einem vertrauenswürdigen lokalen Netz verwenden und niemals ungeprüft ins Internet freigeben.

## Lokale Daten und Sicherungen

| Anwendung | Standardpfad |
|---|---|
| Native App | `~/Library/Application Support/MeinFinanzplan/finanzplan.sqlite` |
| Browser-App | `data/finanzplan.sqlite` |

Persönliche Datenbanken, Exporte, Belege und Build-Artefakte werden nicht versioniert.

Die native JSON-Sicherung enthält die Zuordnung von Belegen, aber nicht die Belegdateien selbst. Beim Umzug auf einen anderen Mac muss der Ordner `Belege` zusätzlich kopiert werden.

## Berechnung der freien Summe

Für das primäre Konto betrachtet die App den Zeitraum bis zur nächsten als verlässlich markierten Einnahme. Diese Einnahme wird nicht vorzeitig als Deckung verwendet. Alle vorher liegenden Ausgaben und Umbuchungen werden chronologisch berücksichtigt.

```text
frei verfügbar = max(0, Ist-Saldo - heute benötigter Betrag)
```

Der heute benötigte Betrag entspricht dem größten erwarteten Rückgang zuzüglich Mindestpuffer. Ohne verlässlichen Zahlungseingang verwendet die App einen konservativen Vorschauzeitraum von 90 Tagen.

## CSV-Import

Der Import akzeptiert UTF-8-Dateien mit Komma oder Semikolon als Trennzeichen. In der Vorschau werden Datum, Bezeichnung und Betrag zugeordnet.

- negative Beträge werden als Ausgaben interpretiert
- positive Beträge werden als Einnahmen interpretiert
- sichere Duplikate werden abgewählt
- mögliche Duplikate werden zur manuellen Prüfung markiert
- historische Importe verändern einen bestätigten Ist-Saldo nicht rückwirkend

## Tests

Native Fachlogik:

```bash
cd native
swift build
swift run VerifyFinanceCore
```

`VerifyFinanceCore` prüft aktuell 129 Szenarien, darunter Liquidität, Wiederholungen, Umbuchungen, Sicherungs-Roundtrips, CSV-Duplikate, Belege und Pfadvalidierung.

Browser-Anwendung:

```bash
npm run check
```

Der Befehl führt Node-Tests, TypeScript-Prüfung und Produktions-Build aus.

## Architektur

```text
.
├── native/
│   ├── Sources/FinanceCore/          # Fachlogik und SQLite-Persistenz
│   ├── Sources/MeinFinanzplan/       # SwiftUI-/AppKit-Oberfläche
│   ├── Sources/VerifyFinanceCore/    # ausführbare Fachprüfungen
│   └── Resources/                    # helle und dunkle App-Icons
├── src/                              # React-Oberfläche
├── server/                           # Fastify, REST und Browser-SQLite
├── test/                             # Browser-Tests
├── docs/                             # Analyse und Umsetzungsdokumentation
└── scripts/                          # Entwicklungswerkzeuge
```

Vertiefende Dokumentation:

- [Fachliche Ausgangsanalyse](docs/excel-analysis.md)
- [Architektur und Berechnungsregeln](docs/implementation-plan.md)
- [Natives Designsystem](native/DESIGN.md)

## Sicherheit und Grenzen

- Keine Cloud-Synchronisierung und kein Online-Banking.
- Der FinTS/HBCI-Code ist nur ein nicht persistierender Machbarkeitstest und nicht in die App integriert.
- Belegdateien und Datenbanken liegen lokal unverschlüsselt im Benutzerprofil.
- Ein App-Start verwendet die echte lokale Datenbank; Tests der Fachlogik arbeiten dagegen mit temporären Datenbanken.
- Die beiden App-Varianten verwenden unterschiedliche Datenmodelle und Speicherorte.

## Lizenz

Für dieses Repository ist derzeit keine Open-Source-Lizenz hinterlegt. Der öffentlich sichtbare Quellcode darf daher nicht automatisch als frei nutzbar oder weiterverteilbar verstanden werden.

---

Entwickelt von **CreativTechnik**.
