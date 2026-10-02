# FinTS-Machbarkeitstest (Schritt 0)

Dieser Ordner enthält noch **keine Integration in die App**. Der Test klärt zuerst mit
der konkreten Bank, ob Girokonto, Tagesgeld und Mastercard über FinTS sichtbar sind und
an welcher Stelle eine TAN verlangt wird.

Das Skript speichert nichts. BLZ, Login, PIN, TAN, FinTS-Endpunkt, Produkt-ID und eine
optional eingegebene Kreditkartennummer bleiben ausschließlich im Arbeitsspeicher des
kurzlebigen Python-Prozesses. Angezeigt werden nur maskierte IBANs und Ergebniszahlen.

## Voraussetzungen

- Python 3.9 oder neuer
- `python-fints` 5.0.0
- HTTPS-Endpunkt der eigenen Bank für FinTS/HBCI PIN/TAN
- eine registrierte FinTS-Produkt-ID

Seit PSD2 verlangt FinTS eine registrierte Produkt-ID. Die offizielle
`python-fints`-Dokumentation beschreibt die Registrierung unter
<https://python-fints.readthedocs.io/en/latest/quickstart.html>.

## Sicher starten

Die folgenden Befehle im Terminal aus dem Repository-Stamm ausführen:

```bash
python3 -m venv /tmp/mein-finanzplan-fints-test
/tmp/mein-finanzplan-fints-test/bin/python -m pip install "fints==5.0.0"
/tmp/mein-finanzplan-fints-test/bin/python native/BankSync/feasibility_check.py
```

Die PIN- und TAN-Eingaben bleiben im Terminal unsichtbar. Keine Zugangsdaten als
Kommandozeilenargumente, Umgebungsvariablen oder Textdateien angeben.

## Auswertung

Am Ende zeigt das Skript:

- ob bereits der Dialogstart eine TAN benötigt,
- ob der Kontenabruf eine TAN benötigt,
- ob Giro- und Tagesgeldkonto in derselben SEPA-Kontenliste sichtbar sind,
- ob der Umsatzabruf je Konto funktioniert und dabei eine TAN verlangt,
- ob die Bank das Kreditkarten-Segment `DKKKU` meldet beziehungsweise die Mastercard
  über den normalen Kontoumsatzabruf erreichbar ist.

Der DKKKU-Aufruf ist in `python-fints` 5.0.0 selbst als reverse-engineered und potenziell
unvollständig gekennzeichnet. Deshalb gilt nur der konkrete Live-Abruf als positives
Ergebnis; eine bloße Segmentmeldung der Bank reicht nicht.

Erst nach diesem Ergebnis wird festgelegt, ob ein stiller Ein-Klick-Abruf technisch
möglich ist und ob die Mastercard in die erste App-Integration aufgenommen werden kann.
