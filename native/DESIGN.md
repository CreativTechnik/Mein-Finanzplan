# Design-System: Mein Finanzplan für macOS

## Leitidee

`Nordlicht Blau` verbindet private Sicherheit mit sachlicher Klarheit. Die App soll sich wie ein ruhiges, hochwertiges Instrument anfühlen: eine helle Inhaltsfläche und eine schwebende blaue Werkzeugleiste innerhalb der echten macOS-Fensterkontur. Die Referenz dient als räumliche und farbliche Richtung, nicht als kopierte Oberfläche.

Ein einziger Wert führt jeden Screen: Auf dem Dashboard ist es der heute frei verfügbare Betrag. Sekundäre Kennzahlen unterstützen diese Entscheidung, statt um Aufmerksamkeit zu konkurrieren.

## Farbkonzept

| Token | Hell | Dunkel | Zweck |
|---|---|---|---|
| `stage` | `#DCEAF5` | `#090E12` | optionale Markenfläche, nicht als Fensterrand |
| `workspace` | `#FBFCFE` | `#11171C` | Kopf- und Navigationsfläche |
| `canvas` | `#F4F8FB` | `#0D1317` | Inhaltsfläche |
| `surface` | `#FFFFFF` | `#182026` | innere Kartenfläche |
| `surfaceShell` | `#EAF2F8` | `#202A31` | äußerer Doppelrand |
| `accent` | `#176FC1` | `#466C82` | Navigation und Aktionen |
| `accentStrong` | `#0B4F91` | `#86A1B1` | große Zahlen und Kontrast |
| `accentSoft` | `#E2F0FB` | `#223039` | ruhige Akzentflächen |
| `textPrimary` | `#102233` | `#E8EDF0` | Primärtext |
| `textSecondary` | `#607487` | `#98A5AD` | Beschriftungen |
| `mist` | `#BFD5E8` | `#566873` | Vergleichsdaten im Chart |

Rot, Grün und Gelb bleiben ausschließlich semantischen Zuständen vorbehalten. Blau ist der einzige dekorative und interaktive Akzent.
Im Dunkelmodus liegt die Oberfläche auf neutralem Graphit statt auf durchgehendem Blau;
der entsättigte Stahlblau-Akzent bleibt Navigation und Interaktion vorbehalten.

## Typografie

- Seitentitel: 30 pt, Semibold, Rounded, leicht negative Laufweite
- Hauptzahl: 62 pt, Bold, Rounded, tabellarische Ziffern
- Abschnitt: 15 pt, Semibold
- Inhalt: 13 pt, Regular oder Semibold
- Meta: 12 pt
- Mikrotext: 11 pt, Medium
- Geldbeträge verwenden immer tabellarische Ziffern

Die Systemschrift bleibt bewusst erhalten, da es sich um eine native macOS-App handelt. Eigenständigkeit entsteht durch Proportion, Laufweite und Hierarchie, nicht durch ein fremdes Webfont-Paket.

## Räumliche Architektur

- Die Oberfläche füllt die native, bereits abgerundete macOS-Fensterkontur vollständig aus.
- Es gibt keinen zweiten dekorativen Außenrahmen und keinen ungenutzten Rand.
- Die Navigation ist eine schmale, schwebende blaue Kapsel mit weißen Symbolen.
- Die aktive Navigation liegt als weiße runde Insel in der Kapsel.
- Hauptkarten verwenden einen Doppelrahmen: 5 pt ruhige Außenschale und eine weiße Innenfläche mit kleinerem konzentrischem Radius.
- Die Hero-Karte verwendet 6 pt Außenschale und mehr Tiefe. Sie bleibt die einzige dominante Karte.

## Dashboard

- Links steht die breite Entscheidungsfläche mit dem frei verfügbaren Betrag und seiner Rechenlogik.
- Rechts stehen zwei kompakte Informationskarten für Wochenbedarf und nächste verlässliche Einnahme.
- Darunter folgt eine interaktive 1-Woche/6-Wochen/1-Jahr-Kurve mit Anfang, Tiefpunkt, Endstand und Datumsauswahl.
- Jedes angelegte Konto besitzt eine eigene, aus seiner Kontofarbe abgeleitete Linie.
- Ein Kontofokus sowie Stufen- und Trackpad-Zoom passen die Y-Achse für stark unterschiedliche Salden an.
- Nur wöchentliche Punktmarker werden angezeigt.

## Buchungen und Statistik

- Die Buchungsart ist eine eigene Symbolauswahl statt eines System-Pickers.
- Der Betrag steht als große, fokussierte Eingabefläche im Zentrum des Dialogs.
- Konto, Kategorie, Datum und Status verwenden ruhige, einheitliche Kontrollflächen.
- Der Buchungsfilter zeigt Symbol, Bezeichnung und echte Trefferzahl.
- Die Statistik bietet 3/6/12 Monate, auswählbare Monatsbalken und eine kompakte Kategorieverteilung.
- Die Kategorievisualisierung bleibt auf 142 pt begrenzt und konkurriert nicht mit dem Monatsverlauf.

## Bewegung und Leistung

- Navigation: kurzer gedämpfter Spring
- Zahlen und Charts: Spring nur bei echten Datenänderungen
- Buttons: leichte Verkleinerung beim Drücken
- Hover nur auf tatsächlich interaktiven Zeilen
- Keine Dauerschleifen, Timer oder automatisch laufenden Animationen
- Kein Blur auf scrollenden Inhaltsflächen
- Schatten sind statisch und flach genug für geringe GPU-Last

## Bedienregeln

- Primäre Aktionen stehen in der Seitenüberschrift, nie neben den macOS-Fensterknöpfen.
- Icon-only-Navigation besitzt Tooltip und Accessibility Label.
- Formulare verwenden native SwiftUI-Controls in einer eigenen, konsistenten Oberfläche mit sichtbarer Validierung.
- Hell ist die visuelle Standarddarstellung. Unter Einstellungen sind Hell, Dunkel und System wählbar.
- Die App verwendet keine WebView und benötigt keinen Browser.
