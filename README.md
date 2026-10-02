# Mein Finanzplan

Eine vollständig lokal laufende Haushalts- und Liquiditätsplanung für macOS. Die Anwendung beantwortet zuerst die Frage: Wie viel Geld ist heute frei verfügbar, wenn alle bekannten Zahlungen bis zur nächsten verlässlichen Einnahme und der gewünschte Mindest-Puffer geschützt bleiben?

Die Ausgangslogik wurde aus einer privaten Haushalts-Arbeitsmappe übernommen und in ein wartbares Konten-, Buchungs- und Regelmodell überführt. Die ursprüngliche Excel-Datei ist nicht Bestandteil dieses Repositories.

## Native macOS-App (empfohlen)

Im Ordner `native/` liegt eine eigenständige SwiftUI-App, die direkt als Programm startet statt im Browser. Sie teilt die fachliche Logik (Konten, Buchungen, Wiederholungen, Liquiditätsberechnung), nutzt aber eine eigene, vom Browser-Server unabhängige lokale Datenbank, damit nichts von der bisherigen Arbeit verloren geht.

```bash
cd native
./build-app.sh
open "dist/Mein Finanzplan.app"
```

Das Skript baut eine Release-Version und verpackt sie als doppelklickbares `.app`-Bundle (lokal ad-hoc signiert). Wer die App dauerhaft im Dock/Spotlight haben möchte, kopiert `dist/Mein Finanzplan.app` nach `~/Applications`.

Details, Architektur und wie die Business-Logik geprüft wird stehen in `native/README.md`.

## Enthalten

- Dashboard mit heute frei verfügbarem Betrag, Wochenbedarf, nächster verlässlicher Einnahme und 90-Tage-Vorschau
- Mehrere Konten mit Ist-Saldo, Plan-Saldo und individuellem Mindest-Puffer
- Einnahmen, Ausgaben und echte Umbuchungen ohne doppelte Vermögenswirkung
- Geplante, gebuchte und stornierte Buchungen
- Monatliche, wöchentliche, jährliche und frei definierte Wiederholungsregeln
- Kategorien, Unterkategorien und Monatsbudgets mit Plan-Ist-Vergleich
- Zeitachse, Statistik und Warnungen bei Puffer-Unterschreitungen
- CSV-Import mit Vorschau und Spaltenzuordnung
- JSON-Datenexport als lokale Sicherung
- Automatischer heller und dunkler Modus, responsive Darstellung und reduzierte Bewegung

## Voraussetzungen

- macOS
- Node.js 22.13 oder neuer
- npm

Die getestete Entwicklungsumgebung verwendet Node.js 26.7.0.

## Produktionsbetrieb

```bash
npm install
npm run build
npm start
```

Danach im Browser öffnen:

```text
http://127.0.0.1:4178
```

Der Server bindet standardmäßig nur an den eigenen Mac. Es gibt keine Cloud, kein Login, keine Bankverbindung und keine Hintergrund-Synchronisation.

## Späterer Zugriff im Heimnetz

Die Oberfläche ist bereits für schmale Browserfenster und Mobilgeräte ausgelegt. Für einen bewussten Test im eigenen, vertrauenswürdigen WLAN kann der Produktionsserver so im lokalen Netz freigegeben werden:

```bash
HOST=0.0.0.0 npm start
```

Danach wird auf dem Mobilgerät die lokale IP-Adresse des Macs mit Port 4178 geöffnet. Dieser Modus besitzt absichtlich kein Login und sollte deshalb nur kurzzeitig in einem vertrauenswürdigen Heimnetz verwendet werden. Standardmäßig bleibt die App sicher auf `127.0.0.1` beschränkt.

## Entwicklung

```bash
npm run dev
```

Der Entwicklungsmodus startet den API-Server und Vite gemeinsam. Für den täglichen Betrieb ist der Produktionsmodus sparsamer, weil kein Dateiwächter und keine Entwicklungswerkzeuge aktiv sind.

## Tests

```bash
npm test
npm run check
```

`npm run check` führt alle Logik- und API-Tests sowie den vollständigen TypeScript- und Produktions-Build aus.

## Lokale Daten

Die SQLite-Datei liegt standardmäßig hier:

```text
data/finanzplan.sqlite
```

Beim ersten Start werden die aus Excel ableitbaren Regeln, Kategorien, Budgets und Planwerte angelegt. Die aktuelle Girokontodeckung war in Excel nicht vorhanden und startet deshalb als zu bestätigende Annahme. Bitte zuerst unter `Konten` prüfen:

1. aktueller Giro-Saldo und Stichtag
2. tatsächlicher Tagesgeld-Saldo
3. gewünschte Mindest-Puffer
4. angenommene Fälligkeitstage der übernommenen Wiederholungen

Unter `Einstellungen` kann jederzeit ein lokaler JSON-Export als Sicherung geladen werden.

## Berechnung der freien Summe

Für das primäre Konto wird der Zeitraum bis zur nächsten als verlässlich markierten Einnahme betrachtet. Diese Einnahme selbst wird nicht vorzeitig als Deckung verwendet. Alle davor liegenden Ausgaben und Umbuchungen werden in Datumsreihenfolge verarbeitet. Der größte erwartete Rückgang plus Mindest-Puffer ergibt den heute benötigten Betrag.

```text
frei verfügbar = max(0, Ist-Saldo - heute benötigter Betrag)
```

Wenn kein verlässlicher Zahlungseingang geplant ist, verwendet die App einen konservativen Vorschauzeitraum von 90 Tagen.

## CSV-Import

Der Import akzeptiert UTF-8-Dateien mit Komma oder Semikolon als Trennzeichen. In der Vorschau werden mindestens Datum, Bezeichnung und Betrag zugeordnet. Negative Beträge werden als Ausgabe, positive Beträge als Einnahme interpretiert. Importierte historische Buchungen verändern einen bereits bestätigten Kontosaldo nicht rückwirkend, fließen aber in Auswertungen ein.

## Batterie und Leistung

- schlanker lokaler Node-Prozess statt Electron-Rahmen
- SQLite mit WAL und normaler Synchronisation für kurze Schreibzugriffe
- keine Hintergrundabfragen und kein Polling
- Wiederholungen und Prognosen werden nur beim Laden oder nach einer Änderung berechnet
- statische Produktionsdateien werden im Browser zwischengespeichert
- Animationen sind kurz und werden bei `Bewegung reduzieren` praktisch deaktiviert
- direkte Icon-Imports halten den Build klein und vermeiden Tausende unnötige Modultransformationen

Für den sparsamen Alltagsbetrieb immer `npm run build` und danach `npm start` verwenden, nicht `npm run dev`.

## Technischer Aufbau

- React und TypeScript für die Oberfläche
- Vite für den Produktions-Build
- Fastify als lokaler HTTP-Server auf `127.0.0.1`
- integriertes `node:sqlite` für die lokale Datenhaltung
- Node Test Runner für automatisierte Tests

Die fachliche Excel-Auswertung steht in `docs/excel-analysis.md`. Architektur, Datenmodell und Berechnungsregeln stehen in `docs/implementation-plan.md`.
