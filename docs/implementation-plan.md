# Umsetzungsplan und Annahmen

## Architektur

- React 19 und Vite für eine responsive Browser-Oberfläche.
- Fastify als kleiner lokaler HTTP-Server auf `127.0.0.1`.
- `node:sqlite` für eine lokale SQLite-Datei ohne externen Datenbankdienst.
- Fachlogik für Wiederholungen, Kontobewegungen und Liquidität in eigenständigen Servermodulen.
- Produktionsbetrieb aus dem einmal gebauten `dist`-Ordner. Kein Electron, keine Cloud und kein periodisches Polling.

## Datenmodell

- `accounts`: Kontoart, Ist-Saldo, Saldo-Stichtag, Mindest-Puffer, Primärkonto, Prüfstatus.
- `categories`: frei verwaltbare Kategorien und Unterkategorien.
- `transactions`: Einnahme, Ausgabe oder Umbuchung mit Plan- und Ist-Datum, Status, Konto, Zielkonto und Notiz.
- `recurrences`: aktive Wiederholungsregeln mit Frequenz, Intervall, Start, Ende und Verlässlichkeit von Einnahmen.
- `budgets`: Monatsbudget pro Kategorie.

Geldbeträge werden als ganze Cent gespeichert. Eine Umbuchung ist genau ein Datensatz mit Quell- und Zielkonto. So wirkt sie auf Konten entgegengesetzt und auf das Gesamtvermögen neutral.

## Heute frei verfügbar

1. Ausgangspunkt ist der aktuelle Ist-Saldo des primären Girokontos.
2. Der Betrachtungszeitraum endet bei der nächsten als verlässlich markierten Einnahme. Ohne solche Einnahme werden 90 Tage betrachtet.
3. Alle geplanten Ausgaben und ausgehenden Umbuchungen bis einschließlich dieses Tages werden konservativ berücksichtigt. Die neue Einnahme selbst finanziert den Zeitraum davor nicht.
4. Für jeden Tag wird der niedrigste erwartete Saldo bestimmt.
5. Der notwendige Startbetrag ist der größte erwartete Abfluss bis zu diesem Tiefpunkt plus Mindest-Puffer.
6. `Heute frei verfügbar = max(0, Ist-Saldo - notwendiger Startbetrag)`.

Beispiel: 500 € Ist-Saldo, 200 € kommende Ausgabe und 100 € Puffer ergeben 300 € notwendigen Startbetrag und 200 € frei verfügbares Geld.

## Bildschirmstruktur

- Übersicht: frei verfügbar, Herleitung, Giro-Saldo, Wochenbedarf, Bedarf bis zur nächsten Einnahme, Warnungen, Handlungsvorschlag und 90-Tage-Verlauf.
- Konten: Ist-, Plan- und Mindest-Saldo mit Bearbeitung.
- Buchungen: Filter, Erfassung und Bearbeitung von Einnahmen, Ausgaben und Umbuchungen.
- Planung: chronologische 90-Tage-Ansicht nach Buchungsereignissen.
- Wiederkehrend: Regeln und Intervalle.
- Budgets: Plan gegen Ist pro Kategorie und Monat.
- Statistik: Einnahmen, Ausgaben und Sparentwicklung.
- Einstellungen: Kategorien sowie vorbereiteter CSV-Import mit Vorschau.

## Dokumentierte Annahmen

- Der Excel-Wert von 2.900 € wird als zu prüfender Startsaldo des Tagesgeldkontos übernommen.
- Der Giro-Saldo und Bargeld-Saldo starten bei 0 €, weil die Excel-Datei keine verlässlichen Ist-Salden enthält.
- Die in der Excel-Datei fehlenden Fälligkeitstage sind sichtbare Annahmen und können in den Wiederholungsregeln geändert werden.
- Variable Monatsbudgets erzeugen nicht automatisch fiktive Buchungen. Nur konkret geplante Buchungen und Wiederholungen wirken auf die taggenaue Liquidität.
- Gebuchte Transaktionen verändern den gespeicherten Ist-Saldo. Eine manuelle Saldoänderung dient als neue Korrektur beziehungsweise Bestätigung.
