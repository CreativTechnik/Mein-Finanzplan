# Gemeinsame Agentenanweisungen

Codex und Claude arbeiten als gleichrangige technische Peers. Codex besitzt viel
historischen Projektkontext, daraus folgt aber keine dauerhafte Weisungs- oder
Integrationsrolle. Vor jeder größeren Änderung müssen
[`AI_RULES.md`](AI_RULES.md) und [`AI_HANDOFF.md`](AI_HANDOFF.md) vollständig gelesen werden.
Die gemeinsamen Regeln dort sind verbindlich und werden hier nicht dupliziert.

## Repository navigation

Read `atlas-map.md` before exploring the repository.
Use it to identify relevant files and avoid scanning unrelated code.

## Arbeitsbeginn

1. Arbeitsverzeichnis und aktuellen Stand mit `pwd` und `git status --short --branch` prüfen.
2. `git diff` und `git diff --staged` lesen.
3. Relevante vorhandene Dateien lesen, bevor Code verändert wird.
4. Prüfen, ob `AI_HANDOFF.md` Änderungen oder offene Arbeiten von Claude nennt.
5. Den Agent Bridge nicht verwenden, solange der Benutzer ihn nicht ausdrücklich wieder
   aktiviert. Abstimmung erfolgt über Git, Worktrees und `AI_HANDOFF.md`.

## Aufgabenverteilung

- Größere Implementierungen benötigen das Review des jeweils anderen Agenten.
- Nach bestandenem Fremd-Review darf jeder der beiden Agenten integrieren.
- Komplexe Änderungen, Debugging, Refactoring, Tests und Release-Prüfungen dürfen von
  beiden Agenten vollständig übernommen werden.

Beide Agenten dürfen Aufgaben vollständig übernehmen. Änderungen des jeweils anderen
sind wie vorhandener Benutzercode zu behandeln: verstehen, berücksichtigen und niemals
blind überschreiben, zurücksetzen oder neu implementieren.

Wenn beide denselben Bereich benötigen, implementiert ein Agent und der andere erstellt
zunächst nur Review-Hinweise. Parallele Codeänderungen erfolgen in getrennten Worktrees;
vor der Integration werden Git-Diffs und `AI_HANDOFF.md` erneut geprüft.

## Direkte Claude-Delegation

- Wenn der Benutzer Claude, eine zweite Modellmeinung oder eine ausdrückliche
  Cross-Model-Prüfung verlangt, den Projekt-Skill `$claude-delegate` verwenden.
- Read-only-Delegation ist der Standard. Claude darf nur auf ausdrücklichen Wunsch
  implementieren und arbeitet dann in einem eigenen Git-Worktree.
- Claudes Ergebnis als Peer-Beitrag prüfen; nicht ungeprüft übernehmen oder integrieren.
- Der Legacy-Agent-Bridge unter `tools/agent-bridge/` bleibt deaktiviert. Der Skill ruft
  ausschließlich die lokale Claude-CLI auf und aktiviert keinen MCP-Server.
- Pro Aufgabe höchstens einen Claude-Aufruf ausführen, sofern der Benutzer keinen
  weiteren Durchlauf verlangt oder ein einmaliger transienter Fehler einen Retry nötig macht.

## Projektspezifische Prioritäten

- Anfragen zur macOS-App betreffen standardmäßig `native/`.
- `native/Sources/FinanceCore` enthält die fachliche Wahrheit der nativen App; UI-Code
  gehört nach `native/Sources/MeinFinanzplan`.
- Die Browser-Variante im Projektstamm ist eine getrennte Implementierung mit eigener
  Datenbank. Änderungen nicht automatisch zwischen beiden Varianten spiegeln.
- Geld bleibt als ganzzahlige Centbeträge modelliert. Umbuchungen bleiben ein Datensatz
  mit Quell- und Zielkonto.
- Keine neuen Dependencies, parallelen Architekturen oder Hintergrunddienste ohne
  nachgewiesenen Bedarf.
- Größere Architekturänderungen vor der Umsetzung kurz in `AI_HANDOFF.md` begründen.

## Wichtige Prüfungen

```bash
# Primäre native macOS-App
cd native
swift build
swift run VerifyFinanceCore

# Browser-Variante, nur wenn sie betroffen ist
cd ..
npm run check
```

Bei Änderungen an Packaging oder Weitergabe zusätzlich die Release-Befehle aus
`AI_RULES.md` verwenden. Nach Abschluss `AI_HANDOFF.md` kurz und sachlich aktualisieren;
veraltete Einträge dabei entfernen. Für parallele Implementierungen einen eigenen
Git-Worktree verwenden.

## Projektort

- Arbeitsordner: dieser Repository-Stamm (`Coding_Space`); auslieferbare Stände gehören nach `../Aktuell`.
- Die verbindliche Projektliste ist `../../PROJEKTE.md`.
- `~/Documents/Anwendung_Finanzen` ist veraltet und nicht mehr zu verwenden.
- iCloud-Konfliktdateien mit Suffix ` 2` nicht verwenden, sondern melden. `*.icloud` vor der Arbeit mit `brctl download "<pfad>"` laden.
