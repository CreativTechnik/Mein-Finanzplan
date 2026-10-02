# Analyse der Excel-Vorlage

Quelle: private Haushalts-Arbeitsmappe, geprüft am 12.09.2026. Die Originaldatei wurde nicht verändert und ist nicht Bestandteil dieses Repositories.

## Aufbau

- Ein Tabellenblatt (`Tabelle1`) mit einem Arbeitsbereich von B1 bis BL70.
- Vier nebeneinanderliegende Jahresblöcke für 2026 bis 2029.
- Pro Jahr stehen Einnahmen, Fix-Ausgaben, variable Ausgaben, eine Monatszusammenfassung und ein separater Sparsaldo untereinander.
- Die Mappe enthält 1.028 Formelzellen und ein Diagramm. Das Diagramm zeigt ausschließlich die Monatsdifferenzen 2027.
- Januar bis Juni 2026 sind ausgeblendet. Die beiden folgenden Spalten heißen `Test` und `Stand`, danach folgen September bis Dezember.

## Fachliche Logik

Die Datei ist ein monatlicher Plan. Detailzeilen werden zu Hauptkategorien addiert, Fix- und variable Ausgaben werden zusammengeführt und von den Einnahmen abgezogen. Der Sparsaldo führt Sparzuflüsse und einzelne Sparentnahmen zusätzlich fort.

Erkannte Einnahmen:

- Gehalt Netto
- Waisenrente Netto
- Kindergeld Netto
- Sonstige Einnahmen

Erkannte Kategorien und Unterkategorien:

- Wohnen: Miete, Kredit, Strom, TV/Streaming, Telefon, Sonstiges
- Mobilität: KFZ-Haftpflicht, Leasing/Kredit, Dauerfahrkarte, Tanken, Reparaturen, Fahrkarten, Sonstiges
- Versicherungen: Privathaftpflicht, Hausrat, Unfallversicherung beziehungsweise Rechtsschutz, BU
- Sparen: Aktien/Fonds, Gold/Silber, Lebensversicherung, Zinskonto
- Lebenshaltung: Lebensmittel, Kleidung, Sonstiges
- Freizeit: Freizeit und weitere sonstige Ausgaben
- Weitere Posten: Bestellungen, Abos, GEZ

Wiederkehrende Planwerte sind durch über Monate wiederholte Beträge erkennbar. Beispiele sind 366 € Waisenrente, 259 € Kindergeld, 250 € Lebensmittel, 110 € Fahrkarten, 20 € Freizeit sowie Versicherungsbeträge von 6 €, 6 €, 6 € und 30 €. Die Sparrate steigt in der Planung von 350 € auf 400 € und später 450 €.

Für 2027 weist die Monatslogik 20.985,08 € Einnahmen, 18.461,08 € Ausgaben und 2.524,00 € Überschuss aus. Für 2028 sind es 21.296,96 €, 18.152,00 € und 3.144,96 €. Für 2029 sind es 21.662,08 €, 18.752,00 € und 2.910,08 €.

## Erkannte Schwächen

- Konten, tatsächliche Salden, Status und Buchungsdaten fehlen.
- Plan- und Ist-Werte sind nicht sauber getrennt.
- Wiederholungen sind kopierte Monatswerte, keine Regeln mit Fälligkeiten.
- Sparraten tauchen als Ausgabe und als Sparsaldo-Zugang auf. In der App müssen sie als Umbuchung modelliert werden.
- Die Einnahmen-Jahressumme 2026 lässt 200 € `Sonstiges` aus. Dadurch ist auch die Jahresdifferenz um 200 € zu niedrig.
- Die Jahreszellen mehrerer Zeilen `Sonstiges` referenzieren versehentlich ganze Zwischensummen statt ihrer eigenen Monatswerte.
- `Unfallversicherung` wird ab 2027 zu `Rechtsschutz`. Das kann eine echte Änderung oder eine umbenannte Kategorie sein.
- Bezeichnungen wie `Entertaintment` und `Sparsaldo Einahmen` sind uneinheitlich.

## Übernahme in den MVP

Die App übernimmt Kategorien, belastbare Monatswerte und erkennbare Wiederholungen. Fehlerhafte Jahressummen werden nicht importiert. Sparraten werden als Umbuchung vom Girokonto auf das Tagesgeld modelliert. Unbekannte Salden und Fälligkeitstage bleiben als Annahmen sichtbar und können bearbeitet werden.
