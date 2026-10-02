# Gemeinsame Projektregeln für Codex und Claude

Diese Datei ist die gemeinsame technische Grundlage beider Agenten. Vor größeren
Änderungen zusätzlich [`AI_HANDOFF.md`](AI_HANDOFF.md) lesen. Chats des jeweils anderen
Agenten gelten nicht als verfügbarer Kontext.

## Projektziel

„Mein Finanzplan“ ist eine lokal laufende Haushalts- und Liquiditätsplanung. Sie verwaltet
Konten, Buchungen, Umbuchungen, wiederkehrende Regeln, Kategorien und Budgets und zeigt
historische sowie geplante Verläufe. Daten bleiben lokal; es gibt derzeit keine Cloud,
kein Benutzerkonto und keine Gerätesynchronisierung.

Die **native macOS-App unter `native/` ist der empfohlene und primäre Produktpfad**.
Daneben existiert im Projektstamm eine ältere lokale Browser-Variante. Beide teilen das
fachliche Thema, aber weder Code noch Datenbank.

## Tatsächliche Architektur

### Native macOS-App

- Swift Package mit Mindestziel macOS 14 und `swift-tools-version: 6.2`.
- `FinanceCore`: Modelle, SQLite-Persistenz, Liquiditäts-/Prognoselogik, CSV-Import und
  PDF-Bericht. Das Target hat keine externen Package-Abhängigkeiten.
- `MeinFinanzplan`: SwiftUI-/AppKit-Oberfläche, Apple Charts und zentraler
  `@MainActor @Observable`-`AppStore`.
- `VerifyFinanceCore`: ausführbares, eigenständiges Prüfprogramm. Es ist aktuell kein
  `swift test`-/XCTest-Target.
- Mutationen laufen über `AppStore` zur `FinanceDatabase`; anschließend lädt der Store
  einen neuen `FinanceSnapshot` und aktualisiert seine ID-Caches.
- Native Datenbank:
  `~/Library/Application Support/MeinFinanzplan/finanzplan.sqlite`.

### Lokale Browser-Variante

- React 19 und TypeScript für die Oberfläche, Vite für Entwicklung und Build.
- Fastify 5 als lokaler HTTP-Server, standardmäßig auf `127.0.0.1:4178`.
- `node:sqlite` für Persistenz; REST-/Service-Logik liegt unter `server/`.
- Browser-Datenbank: `data/finanzplan.sqlite` oder der Wert von
  `FINANZPLAN_DB_PATH`.
- Node Test Runner für API- und Fachlogiktests.

### Wichtige fachliche Invarianten

- Geldbeträge werden als ganze Cent (`Int` beziehungsweise Integer) gespeichert, nicht
  als Fließkommazahlen.
- Datumswerte werden im Modell als ISO-Strings `YYYY-MM-DD` geführt.
- Eine Umbuchung ist genau ein Datensatz mit Quell- und Zielkonto. Sie verändert beide
  Konten entgegengesetzt und bleibt für das Gesamtvermögen neutral.
- Buchungsstatus sind geplant, gebucht und storniert. Stornierte Buchungen wirken nicht
  auf Prognosen.
- Verlässliche geplante Einnahmen bestimmen den Liquiditätshorizont; sie dürfen nicht
  vor ihrem Datum als verfügbare Deckung behandelt werden.
- CSV-Historien können als gebucht importiert werden, ohne einen bereits bestätigten
  Ist-Saldo rückwirkend zu verändern.
- Native und Browser-Datenbank sind nicht austauschbar. Nur die dafür vorgesehenen
  JSON-Import-/Exportwege verwenden.

## Verwendete Technologien

| Bereich | Tatsächlich eingesetzt |
| --- | --- |
| Native UI | SwiftUI, AppKit, Charts, Observation |
| Native Logik/Persistenz | Swift 6, Foundation, systemweites SQLite |
| Native Build | Swift Package Manager, Shell, `lipo`, `codesign`, `pkgbuild`, `productbuild`, `hdiutil` |
| Browser UI | React 19, TypeScript 7, Vite 8, Phosphor Icons |
| Browser Server | Node.js ESM, Fastify 5, `node:sqlite` |
| Browser Tests | Node Test Runner |

Analysierter lokaler Werkzeugstand am 13.09.2026: Swift 6.3.3, Node 26.7.0 und
npm 11.19.0. Die deklarierte Mindestversion der Browser-Variante ist Node 22.13.0.

## Wichtige Verzeichnisse und Dateien

```text
native/                              primäre macOS-App
  Package.swift                      Swift-Paket und Targets
  Sources/FinanceCore/               Fachlogik und native Persistenz
  Sources/MeinFinanzplan/            SwiftUI-App und AppStore
  Sources/VerifyFinanceCore/         bestehende native Fachprüfungen
  Resources/                         helle/dunkle App-Icons
  MeinFinanzplan.entitlements        minimale Kalenderberechtigung der Signatur
  distribution/                      Anleitung und Fallback-Installer
  releases/                          erzeugte Release-Artefakte
  DESIGN.md                          natives Designsystem „Nordlicht Blau“
src/                                 React-Oberfläche der Browser-Variante
server/                              Fastify, SQLite und Browser-Fachlogik
test/                                Node-Tests
data/                                lokale Browser-Datenbank; kein Fixture-Ordner
docs/                                Excel-Analyse und ursprünglicher Umsetzungsplan
scripts/                             Entwicklungs- und Excel-Analysewerkzeuge
tools/agent-bridge/                  vorhandenes Legacy-Werkzeug; derzeit nicht verwenden
```

`dist/`, `native/dist`, `.build*`, `native/releases/`, Datenbanken und generierte
PDF-/ZIP-Artefakte sind Build- oder Laufzeitdaten und keine Quelle für Änderungen.
Quellcode immer in `Sources/`, `src/` oder `server/` bearbeiten.

## Parallele Zusammenarbeit

- Git ist die technische Quelle der Wahrheit; `AI_RULES.md` und `AI_HANDOFF.md` sind der
  gemeinsame, chatunabhängige Kontext.
- Der Agent Bridge wird auf Wunsch des Benutzers derzeit nicht verwendet. Ihn nur nach
  einer neuen ausdrücklichen Freigabe wieder einsetzen.
- Für parallele Implementierungen getrennte Git-Worktrees und eigene Branches verwenden.
- Vor Änderungen und Integration immer Status und Diffs aller betroffenen Worktrees
  prüfen. Gleiche Dateien nicht gleichzeitig bearbeiten.
- Ein Agent implementiert einen überlappenden Bereich, der andere reviewt zunächst nur.
- `AI_HANDOFF.md` bleibt kurz und enthält nur integrationsrelevante Informationen.

## Build-, Start- und Testbefehle

Alle nativen Befehle aus `native/` ausführen:

```bash
cd native

# Entwicklung
swift build
swift run MeinFinanzplan

# Bestehende Fachprüfungen
swift run VerifyFinanceCore

# Universal-App und Verteilung
./build-app.sh
./build-dmg.sh
./build-pkg.sh
./build-share-zip.sh

# Prüft ZIP, Prüfsummen, beide Architekturen, Signatur,
# Update-PKG, Quarantäne-Fallback und Start ohne Netzwerk
./test-release-sandbox.sh
```

`build-share-zip.sh` erwartet, dass App, DMG und beide PKGs zuvor gebaut wurden. Die
Ausgabe landet versionsbezogen unter `native/releases/v<VERSION>/`; `native/dist` ist ein
Symlink auf das aktuelle Release. Die App wird derzeit ad-hoc signiert und ist ohne Apple
Developer ID nicht notarisiert.

Browser-Befehle aus dem Projektstamm:

```bash
npm install
npm run dev       # Fastify und Vite im Entwicklungsmodus
npm start         # gebaute lokale Browser-Anwendung
npm test          # Node-Tests
npm run build     # TypeScript- und Vite-Build
npm run check     # npm test && npm run build
```

## Coding Style

### Swift

- Bestehenden Swift-6-Stil und vier Leerzeichen Einrückung beibehalten.
- Daten standardmäßig als `struct` oder `enum`, `let` vor `var`; Klassen nur bei
  benötigter Identität beziehungsweise gemeinsamem Zustand.
- Modelle, die Isolationsgrenzen überschreiten, bleiben wertbasiert und `Sendable`.
- Die UI und `AppStore` bleiben Main-Actor-isoliert. `FinanceCore` nicht pauschal auf den
  Main Actor setzen.
- Keine nebenläufige Architektur auf Verdacht einführen. Erst algorithmisch optimieren
  und messen; bei Bedarf strukturierte Concurrency verwenden, nicht wahllos
  `Task.detached` oder globale Queues.
- Fehler über aussagekräftige Error-Typen beziehungsweise `throws` weitergeben;
  `fatalError` nur für nicht wiederherstellbare Programm-Invarianten.
- Wiederverwendbare UI-Bausteine und Design-Tokens aus `FormComponents.swift` und
  `Theme.swift` verwenden. Bestehende Regeln in `native/DESIGN.md` beachten.

### TypeScript und JavaScript

- ESM-Struktur und bestehende Zweileerzeichen-Einrückung beibehalten.
- UI, API-Routen, Validierung, Service-/Fachlogik und Datenbankzugriff getrennt halten.
- Eingaben an der Servergrenze validieren; SQL und Saldowirkung nicht in React-Code
  verschieben.
- Keine neuen Laufzeitabhängigkeiten, wenn Plattform- oder bestehende Projektmittel die
  Aufgabe erfüllen.

## Regeln für Änderungen

1. Vor größeren Änderungen `AI_RULES.md`, `AI_HANDOFF.md`, `git status`, Diffs und die
   Live-Statusanzeige sowie die betroffenen Dateien lesen.
2. Vor Schreibzugriffen einen Agent-Claim setzen. Änderungen außerhalb der reservierten
   Dateien erfordern einen aktualisierten Claim.
3. Benutzeränderungen und Änderungen des anderen Agenten nie blind zurücksetzen,
   überschreiben oder durch generierten Ersatzcode verdrängen.
4. Eine Mac-App-Anforderung standardmäßig ausschließlich in `native/` umsetzen. Die
   Browser-Variante nur ändern, wenn sie ausdrücklich betroffen ist.
5. Schemaänderungen müssen vorhandene lokale Daten und ältere JSON-Sicherungen
   berücksichtigen. Keine Datenbank löschen oder neu anlegen, um eine Migration zu
   umgehen.
6. VERSION, BUILD_NUMBER und Release-Artefakte nur bei einer tatsächlich gewünschten
   Release-Erstellung ändern.
7. Keine Secrets, API-Keys, privaten Finanzdaten oder Zugangsdaten in Dokumentation,
   Tests, Logs oder Fixtures aufnehmen.
8. Neue Dependencies nur mit konkreter Begründung und nach Prüfung vorhandener
   Plattformmittel. Lockfiles nur verändern, wenn sich Dependencies wirklich ändern.

## Regeln für Refactoring

- Funktionierende Bereiche nicht komplett neu implementieren, nur weil eine alternative
  Struktur möglich wäre.
- Erst Verhalten und Tests verstehen, dann kleine, überprüfbare Schritte durchführen.
- Fachlogik nicht in SwiftUI-Views oder React-Komponenten duplizieren.
- Native Persistenzlogik in `FinanceDatabase`, Berechnungen in `FinanceCore` und
  Präsentationszustand in `AppStore` belassen.
- Größere Architekturänderungen vor dem ersten Code-Patch in `AI_HANDOFF.md` mit Problem,
  Grund, betroffenen Bereichen und geplantem Migrationsweg festhalten.
- Leistungsänderungen messen oder durch klare Komplexitätsverbesserungen belegen; keine
  Concurrency als pauschale Performance-Lösung einführen.

## Regeln für Tests

- Nach jeder fachlich relevanten nativen Änderung mindestens `swift build` und
  `swift run VerifyFinanceCore` ausführen.
- Neue native Fachlogik im bestehenden `VerifyFinanceCore`-Prüfprogramm abdecken, solange
  kein separates Test-Target eingeführt wurde. Tests verwenden temporäre Datenbanken und
  dürfen keine Benutzerdaten öffnen.
- Nach Änderungen der Browser-Variante `npm run check` ausführen.
- UI-Änderungen zusätzlich durch Start der echten App prüfen; relevante Interaktion sowie
  hellen und dunklen Modus kontrollieren.
- Änderungen an Build, Signatur, Installer oder Update-Paket erfordern die vollständige
  Release-Kette und `./test-release-sandbox.sh`.
- Fehlerhafte Tests nicht deaktivieren oder Erwartungen nur an die Implementierung
  anpassen. Ursache beheben oder das offene Problem in `AI_HANDOFF.md` dokumentieren.
- In der Übergabe exakt notieren, welche Prüfungen ausgeführt wurden und welche noch
  ausstehen.

## Gemeinsame Übergabe

`AI_HANDOFF.md` ist kein Protokoll und kein Changelog. Die Datei bleibt kurz und enthält
nur aktive Aufgabe, relevante aktuelle Änderungen, offene Probleme, Architekturentscheide
und ausstehende Prüfungen. Ein Agent ersetzt veraltete Angaben, statt immer neue Historie
anzuhängen.

Die lokale Git-Historie ist die technische Integrationsgrundlage. Ein GitHub-Remote ist
optional und derzeit nicht eingerichtet. Die `.gitignore` schützt persönliche
Datenbanken, lokale Claude-Einstellungen, Build-Caches und Release-Artefakte.
