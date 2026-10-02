# AI-Handoff

Stand: 02.10.2026

## Aktuelle Aufgabe

- Der bereinigte Quellstand ist öffentlich unter
  `https://github.com/CreativTechnik/Mein-Finanzplan`; lokale Daten, Build-Artefakte,
  Agentenwerkzeuge und die frühere persönliche Commit-Historie wurden nicht veröffentlicht.
- `Mein Finanzplan v0.15.2` (Build 20) ist gebaut: Duplikat-Erkennung beim CSV-Import,
  Menüleisten-Zusammenfassung und Belege an Buchungen. Artefakte liegen unter
  `native/releases/v0.15.2/` (App, DMG, Vollinstaller, Update-PKG, Weitergabe-ZIP).
- FinTS/HBCI befindet sich bewusst weiter in Schritt 0: Ein nicht persistierender,
  interaktiver Machbarkeitstest liegt unter `native/BankSync/`. Modell, Datenbank, UI
  und App-Bundle wurden dafür nicht verändert.

## Relevante Änderungen

- **Duplikat-Erkennung:** `ImportDuplicateDetector` (`FinanceCore/ImportDeduplication.swift`)
  vergleicht CSV-Zeilen mit bestehenden Buchungen (Konto, Art, Betrag, Datum, normalisierter
  Text) per Mengen-Abgleich; sicher = abgewählt, möglich (±3 Tage, geplante Buchung,
  anderer Text) = markiert. Identische Zeilen innerhalb einer Datei erhalten Fingerprints
  mit Suffix `#n` (behebt stilles Verwerfen zweier gleicher Käufe am selben Tag).
  `FinanceBackup.bankImportRecords` (optional) erhält Import-Fingerprints über Restore.
- **Menüleiste:** `MenuBarExtra` in `MeinFinanzplanApp.swift` (`WindowGroup` hat jetzt
  `id: "main"`), Ansicht in `MenuBarSummaryView.swift`, Auswahl der nächsten Buchungen in
  `FinanceCore/UpcomingSummary.swift`. Standard: Symbol an, Betrag in der Leiste aus. Bei
  gesperrter App keine Beträge oder Titel. Einstellungen: `menuBarEnabled`,
  `menuBarShowAmount`, `menuBarHideAmounts` (UserDefaults, nicht im Backup).
  Ein echtes WidgetKit-Widget bleibt ohne Developer ID, App Group und Xcode-Build offen.
- **Belege:** Neue Tabelle `entry_attachments` (Kaskade auf `entries`), Dateien
  inhaltsadressiert als `<sha256>.<ext>` in `Application Support/MeinFinanzplan/Belege/`
  (`FinanceCore/AttachmentStore.swift`; PDF, JPEG, PNG, HEIC, TIFF, max. 25 MB, Signaturprüfung).
  Änderungen im Buchungsdialog werden erst beim Speichern angewendet
  (`AppStore.saveEntry`). `FinanceBackup.attachments` (optional) enthält nur Metadaten;
  `storedName` wird beim Import auf das Hash-Muster geprüft. Nach `importData` bleiben
  Dateien bewusst liegen (Recovery-Datei). Ältere App-Versionen verlieren die
  Beleg-Zuordnung bei einem Roundtrip stillschweigend.
- `schemaVersion` der Sicherung bleibt 1; alle neuen Schlüssel sind optional.

## Offene Probleme

- Der echte FinTS-Test benötigt noch Bank-Endpunkt, registrierte Produkt-ID und die nur
  lokal im Terminal eingegebenen Zugangsdaten. Erst sein Ergebnis entscheidet über
  TAN-UI, Mastercard-Unterstützung und die weitere Implementierung ab Schritt 1.
- Neue Oberfläche (Import-Badges, Menüleiste, Beleg-Abschnitt) ist nur kompiliert und
  per App-Start ohne Absturz geprüft, nicht visuell oder interaktiv (kein Screenshot-Zugriff).
  Zu prüfen: Hell/Dunkel, Fenster schließen und über „App öffnen“ wiederherstellen,
  Drag & Drop von Belegen, Menüleiste bei gesperrter App.
- „Sicherung mit Belegen“ (Ordner-Export) ist nicht umgesetzt; beim Umzug den Ordner
  `Belege` manuell kopieren.
- Ein App-Start öffnet immer die echte Datenbank (`HOME`-Override isoliert nicht).
- Der Build ist mangels Apple Developer ID ad-hoc signiert und nicht notarisiert. Auf
  einem fremden Mac den mitgelieferten Installer verwenden; macOS kann nach Updates den
  Kalenderzugriff erneut abfragen.
- `test-release-sandbox.sh` benötigt `rg` (ripgrep) im `PATH`; ohne fehlt die
  Update-only-Prüfung mit einer irreführenden Fehlermeldung.

## Architekturentscheidungen

- `FinanceCore` bleibt fachliche Wahrheit; App-Code liegt getrennt im macOS-Schlüsselbund
  und ist absichtlich kein Bestandteil von Finanzmodell oder Sicherungsformat.
- Die FinTS-App-Integration wird nicht vorgezogen: Erst Schritt 0 real prüfen, danach
  Datenmodell, kurzlebigen stdin/stdout-Helper, Bundle und UI in dieser Reihenfolge bauen.
  Die Duplikat-Erkennung ist dafür die vorgesehene gemeinsame Import-Prüfung.
- Beleg-Hashing und -Kopie laufen synchron im Speichervorgang (Dateien ≤ 25 MB).

## Tests

- GitHub-Stand am 02.10.2026: `swift run --scratch-path .build-verify-github VerifyFinanceCore`
  bestanden (**129/129**, 0 Fehler). Ein vollständiges `swift build` war in der aktuell
  ausgewählten Command-Line-Tools-Umgebung wegen des fehlenden Apple-Systemplugins
  `SwiftUIMacros` nicht erneut ausführbar; die letzte vollständige Release-Prüfung bleibt
  die unten dokumentierte erfolgreiche Prüfung.
- `swift build`: bestanden.
- `swift run VerifyFinanceCore`: **129/129**, 0 Fehler (neu: Duplikat-Erkennung, gleiche
  Käufe am selben Tag, Fingerprint-Roundtrip, Menüleisten-Auswahl, Belege inkl. Deduplizierung,
  Rollback, Pfad-Angriff im Backup, alte Sicherungen ohne neue Schlüssel).
- App-Start (Debug) ca. 9 s ohne Absturz; UI nicht visuell geprüft.
- Universal-App, DMG, Vollinstaller, Update-PKG und Weitergabe-ZIP für v0.15.2 Build 20 gebaut.
- `test-release-sandbox.sh`: Prüfsummen, Signatur, `x86_64` + `arm64`, Update-only-
  Installation, Gatekeeper-Fallback und Offline-Start bestanden (0,0 % CPU, ca. 23 MB RSS).
