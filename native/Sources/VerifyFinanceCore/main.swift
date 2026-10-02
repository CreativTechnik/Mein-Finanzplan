import Foundation
import FinanceCore

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ label: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if condition() {
        print("  ok  - \(label)")
    } else {
        failures += 1
        print("  FAIL - \(label) (\(file):\(line))")
    }
}

func makeAccount(id: String = "checking", balance: Int, buffer: Int = 0, isPrimary: Bool = true) -> Account {
    Account(id: id, name: id, kind: .checking, currentBalanceCents: balance, balanceAsOf: "2026-09-01", minimumBufferCents: buffer, colorHex: "#000000", isPrimary: isPrimary, needsReview: false)
}

func balance(_ database: FinanceDatabase, _ accountID: String) throws -> Int? {
    try database.snapshot().accounts.first { $0.id == accountID }?.currentBalanceCents
}

print("Liquiditätsberechnung")

do {
    let account = makeAccount(balance: 50_000, buffer: 10_000)
    let expense = FinanceEntry(id: "expense", title: "Versicherung", amountCents: 20_000, kind: .expense, accountID: "checking", plannedDate: "2026-09-05")
    let salary = FinanceEntry(id: "salary", title: "Gehalt", amountCents: 100_000, kind: .income, accountID: "checking", plannedDate: "2026-09-10", isReliable: true)
    let snapshot = FinanceEngine.snapshot(accounts: [account], entries: [expense, salary], rules: [], today: "2026-09-01", days: 90)
    let liquidity = snapshot.liquidity
    expect(liquidity?.horizon == "2026-09-10", "horizon ist die nächste verlässliche Einnahme")
    expect(liquidity?.requiredCents == 30_000, "benötigter Betrag schützt Ausgabe und Puffer")
    expect(liquidity?.availableCents == 20_000, "frei verfügbar = Saldo - benötigt")
    expect(liquidity?.shortfallCents == 0, "keine Unterdeckung")
}

do {
    let checking = makeAccount(id: "checking", balance: 100_000)
    let savings = makeAccount(id: "savings", balance: 200_000, isPrimary: false)
    let transfer = FinanceEntry(id: "transfer", title: "Sparrate", amountCents: 25_000, kind: .transfer, accountID: "checking", transferAccountID: "savings", plannedDate: "2026-09-02")
    let snapshot = FinanceEngine.snapshot(accounts: [checking, savings], entries: [transfer], rules: [], today: "2026-09-01", days: 3)
    expect(Set(snapshot.forecast.map(\.accountID)) == Set(["checking", "savings"]), "Prognose enthält eine Datenreihe für jedes Konto")
    expect(snapshot.forecast.last { $0.accountID == "checking" }?.balanceCents == 75_000, "Umbuchung verringert Quellkonto")
    expect(snapshot.forecast.last { $0.accountID == "savings" }?.balanceCents == 225_000, "Umbuchung erhöht Zielkonto")
}

do {
    let account = makeAccount(balance: 50_000)
    let cancelled = FinanceEntry(id: "cancelled", title: "Storniert", amountCents: 90_000, kind: .expense, accountID: "checking", plannedDate: "2026-09-02", status: .cancelled)
    let snapshot = FinanceEngine.snapshot(accounts: [account], entries: [cancelled], rules: [], today: "2026-09-01", days: 5)
    expect(snapshot.forecast.allSatisfy { $0.balanceCents == 50_000 }, "stornierte Buchungen bleiben ohne Wirkung")
}

print("Wiederholungen")

func rentRule(frequency: RecurrenceFrequency = .monthly, interval: Int = 1, startDate: String = "2027-01-31", endDate: String? = nil, dueDay: Int? = 31) -> RecurringRule {
    RecurringRule(id: "rent", title: "Miete", amountCents: 80_000, kind: .expense, accountID: "checking", categoryID: "housing", frequency: frequency, interval: interval, startDate: startDate, endDate: endDate, dueDay: dueDay)
}

do {
    let dates = FinanceEngine.occurrences(for: rentRule(), from: "2027-01-01", through: "2027-04-30").map(\.plannedDate)
    expect(dates == ["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30"], "monatliche Regel behält Ankertag nach kurzem Monat")
}

do {
    let biweekly = rentRule(frequency: .weekly, interval: 2, startDate: "2026-09-01", endDate: "2026-10-01", dueDay: nil)
    let dates = FinanceEngine.occurrences(for: biweekly, from: "2026-09-01", through: "2026-12-31").map(\.plannedDate)
    expect(dates == ["2026-09-01", "2026-09-15", "2026-09-29"], "zweiwöchentliches Intervall respektiert Enddatum")
}

do {
    let account = makeAccount(balance: 0)
    let booked = FinanceEntry(id: "tx-feb", title: "Miete", amountCents: 80_000, kind: .expense, accountID: "checking", recurrenceID: "rent", plannedDate: "2027-02-28", status: .booked)
    let snapshot = FinanceEngine.snapshot(accounts: [account], entries: [booked], rules: [rentRule()], today: "2027-01-01", days: 90)
    let occurrenceDates = snapshot.occurrences.map(\.plannedDate)
    expect(!occurrenceDates.contains("2027-02-28"), "gebuchte Transaktion ersetzt generierten Termin")
    expect(occurrenceDates.contains("2027-01-31") && occurrenceDates.contains("2027-03-31"), "andere Termine bleiben generiert")
}

print("Datenbank")

func makeDatabase() throws -> FinanceDatabase {
    let url = FileManager.default.temporaryDirectory.appending(path: "finanzplan-verify-\(UUID().uuidString).sqlite")
    return try FinanceDatabase(fileURL: url)
}

do {
    let database = try makeDatabase()
    let before = try database.snapshot()
    guard let checking = before.accounts.first(where: { $0.kind == .checking }), let savings = before.accounts.first(where: { $0.kind == .savings }) else {
        throw FinanceDatabaseError.invalid("Seed-Konten fehlen.")
    }
    let startingBalance = checking.currentBalanceCents

    let expense = FinanceEntry(id: UUID().uuidString, title: "Testbuchung", amountCents: 10_000, kind: .expense, accountID: checking.id, plannedDate: "2026-09-02", actualDate: "2026-09-02", status: .booked, affectsBalance: true)
    try database.addEntry(expense)
    let afterExpense = try balance(database, checking.id)
    expect(afterExpense == startingBalance - 10_000, "gebuchte Ausgabe verringert Saldo")

    var reduced = expense
    reduced.amountCents = 7_500
    try database.updateEntry(reduced)
    let afterUpdate = try balance(database, checking.id)
    expect(afterUpdate == startingBalance - 7_500, "Bearbeiten korrigiert den Saldo-Effekt")

    let transfer = FinanceEntry(id: UUID().uuidString, title: "Umbuchung", amountCents: 20_000, kind: .transfer, accountID: checking.id, transferAccountID: savings.id, plannedDate: "2026-09-03", actualDate: "2026-09-03", status: .booked, affectsBalance: true)
    try database.addEntry(transfer)
    let checkingAfterTransfer = try balance(database, checking.id)
    let savingsAfterTransfer = try balance(database, savings.id)
    expect(checkingAfterTransfer == startingBalance - 7_500 - 20_000, "Umbuchung belastet Quellkonto")
    expect(savingsAfterTransfer == savings.currentBalanceCents + 20_000, "Umbuchung begünstigt Zielkonto")

    try database.deleteEntry(id: transfer.id)
    let checkingAfterDelete = try balance(database, checking.id)
    let savingsAfterDelete = try balance(database, savings.id)
    expect(checkingAfterDelete == startingBalance - 7_500, "Löschen macht Quellkonto-Effekt rückgängig")
    expect(savingsAfterDelete == savings.currentBalanceCents, "Löschen macht Zielkonto-Effekt rückgängig")
}

do {
    let database = try makeDatabase()
    guard let checking = try database.snapshot().accounts.first(where: { $0.kind == .checking }) else {
        throw FinanceDatabaseError.invalid("Seed-Konto fehlt.")
    }
    let startingBalance = checking.currentBalanceCents
    let imported = FinanceEntry(id: UUID().uuidString, title: "CSV-Import", amountCents: 5_000, kind: .expense, accountID: checking.id, plannedDate: "2026-09-02", actualDate: "2026-09-02", status: .booked, note: "Aus CSV", affectsBalance: false)
    try database.addEntry(imported)
    let afterImport = try balance(database, checking.id)
    expect(afterImport == startingBalance, "CSV-Import ohne Saldowirkung lässt Saldo unverändert")
    try database.deleteEntry(id: imported.id)
    let afterDelete = try balance(database, checking.id)
    expect(afterDelete == startingBalance, "Löschen des Imports lässt Saldo unverändert")
}

do {
    let database = try makeDatabase()
    let exportURL = FileManager.default.temporaryDirectory.appending(path: "finanzplan-backup-\(UUID().uuidString).json")
    try database.upsertBudget(month: "2027-01", categoryID: "cat-food", plannedCents: 42_000)
    try database.exportData(to: exportURL)

    let backup = try JSONDecoder().decode(FinanceBackup.self, from: Data(contentsOf: exportURL))
    expect(backup.schemaVersion == 1, "Export enthält eine versionierte Sicherung")
    expect(backup.budgets.contains { $0.month == "2027-01" && $0.plannedCents == 42_000 }, "Export enthält Budgets aller Monate")

    guard let checking = try database.snapshot().accounts.first(where: { $0.kind == .checking }) else {
        throw FinanceDatabaseError.invalid("Seed-Konto fehlt.")
    }
    let afterBackup = FinanceEntry(id: "nach-sicherung", title: "Nur danach", amountCents: 1_000, kind: .expense, accountID: checking.id, plannedDate: "2026-09-04")
    try database.addEntry(afterBackup)
    let recoveryURL = try database.importData(from: exportURL)
    let restored = try database.snapshot()
    expect(!restored.entries.contains { $0.id == afterBackup.id }, "Import ersetzt den Datenstand vollständig")
    expect(FileManager.default.fileExists(atPath: recoveryURL.path), "Import erstellt vorher eine automatische Rückfallebene")

    let invalidURL = FileManager.default.temporaryDirectory.appending(path: "finanzplan-invalid-\(UUID().uuidString).json")
    try Data("{nicht-gueltig}".utf8).write(to: invalidURL)
    let beforeInvalid = try database.snapshot().entries
    do {
        _ = try database.importData(from: invalidURL)
        expect(false, "ungültige Sicherung wird abgewiesen")
    } catch {
        expect(true, "ungültige Sicherung wird abgewiesen")
    }
    let afterInvalid = try database.snapshot().entries
    expect(afterInvalid == beforeInvalid, "fehlerhafter Import verändert keine Daten")
}

do {
    let database = try makeDatabase()
    try database.addCategory(name: "Kaution", kind: .transfer, iconName: "key")
    guard var category = try database.snapshot().categories.first(where: { $0.name == "Kaution" }) else {
        throw FinanceDatabaseError.invalid("Test-Kategorie fehlt.")
    }
    expect(category.iconName == "key", "gewähltes Kategorie-Symbol wird gespeichert")
    category.iconName = "house"
    try database.updateCategory(category)
    let updatedIcon = try database.snapshot().categories.first(where: { $0.id == category.id })?.iconName
    expect(updatedIcon == "house", "Kategorie-Symbol lässt sich bearbeiten")

    let legacyCategoryData = Data(#"{"id":"legacy","name":"Altbestand","kind":"EXPENSE"}"#.utf8)
    let legacyCategory = try JSONDecoder().decode(FinanceCategory.self, from: legacyCategoryData)
    expect(legacyCategory.iconName == "tag", "alte Sicherungen erhalten ein kompatibles Standardsymbol")
}

do {
    let database = try makeDatabase()
    let snapshot = try database.snapshot()
    let month = String(snapshot.today.prefix(7))
    guard let checking = snapshot.accounts.first(where: { $0.kind == .checking }),
          let savings = snapshot.accounts.first(where: { $0.kind == .savings }) else {
        throw FinanceDatabaseError.invalid("Seed-Konten fehlen.")
    }
    let transfer = FinanceEntry(
        id: UUID().uuidString,
        title: "Sparziel-Test",
        amountCents: 30_000,
        kind: .transfer,
        accountID: checking.id,
        transferAccountID: savings.id,
        categoryID: "cat-savings",
        plannedDate: snapshot.today,
        actualDate: snapshot.today,
        status: .booked
    )
    try database.addEntry(transfer)
    try database.upsertBudget(month: month, categoryID: "cat-savings", plannedCents: 50_000)
    let income = FinanceEntry(
        id: UUID().uuidString,
        title: "Einnahmeziel-Test",
        amountCents: 80_000,
        kind: .income,
        accountID: checking.id,
        categoryID: "cat-salary",
        plannedDate: snapshot.today,
        actualDate: snapshot.today,
        status: .booked
    )
    try database.addEntry(income)
    try database.upsertBudget(month: month, categoryID: "cat-salary", plannedCents: 100_000)
    let goalSnapshot = try database.snapshot()
    let savingsGoal = goalSnapshot.budgets.first { $0.categoryID == "cat-savings" }
    let incomeGoal = goalSnapshot.budgets.first { $0.categoryID == "cat-salary" }
    expect(savingsGoal?.actualCents == 30_000, "gebuchte Umbuchung zählt zum Sparziel")
    expect(incomeGoal?.actualCents == 80_000, "gebuchte Einnahme zählt zum Einnahmeziel")
}

do {
    let database = try makeDatabase()
    let snapshot = try database.snapshot()
    guard let checking = snapshot.accounts.first(where: { $0.kind == .checking }),
          let savings = snapshot.accounts.first(where: { $0.kind == .savings }) else {
        throw FinanceDatabaseError.invalid("Seed-Konten fehlen.")
    }
    let startingCheckingBalance = checking.currentBalanceCents
    var recoloredChecking = checking
    recoloredChecking.colorHex = "#B45F69"
    try database.updateAccount(recoloredChecking)
    let savedAccountColor = try database.snapshot().accounts.first(where: { $0.id == checking.id })?.colorHex
    expect(savedAccountColor == "#B45F69", "Diagrammfarbe des Kontos wird gespeichert")
    let transfer = FinanceEntry(
        id: UUID().uuidString,
        title: "Verknüpfte Umbuchung",
        amountCents: 12_000,
        kind: .transfer,
        accountID: checking.id,
        transferAccountID: savings.id,
        plannedDate: snapshot.today,
        actualDate: snapshot.today,
        status: .booked,
        affectsBalance: true
    )
    try database.addEntry(transfer)
    try database.deleteAccount(id: savings.id)
    let afterDeletion = try database.snapshot()
    expect(!afterDeletion.accounts.contains { $0.id == savings.id }, "Konto lässt sich löschen")
    expect(!afterDeletion.entries.contains { $0.id == transfer.id }, "verknüpfte Buchung wird beim Kontolöschen entfernt")
    expect(afterDeletion.accounts.first(where: { $0.id == checking.id })?.currentBalanceCents == startingCheckingBalance, "Kontolöschung korrigiert verbundene Salden")
}

print("Archiv, Kategorien und CSV")

do {
    let database = try makeDatabase()
    let snapshot = try database.snapshot(today: "2026-09-13")
    guard let checking = snapshot.accounts.first(where: { $0.kind == .checking }) else { throw FinanceDatabaseError.invalid("Seed-Konto fehlt.") }
    let old = FinanceEntry(id: "old-manual", title: "Alter Einkauf", amountCents: 1_250, kind: .expense, accountID: checking.id, categoryID: "cat-food", plannedDate: "2026-08-15", actualDate: "2026-08-15", status: .booked)
    let review = FinanceEntry(id: "old-review", title: "Noch zuordnen", amountCents: 500, kind: .expense, accountID: checking.id, plannedDate: "2026-08-16", actualDate: "2026-08-16", status: .booked)
    try database.addEntry(old)
    try database.addEntry(review)
    let archived = try database.snapshot(today: "2026-09-13")
    expect(archived.entries.first(where: { $0.id == old.id })?.isArchived == true, "alte kategorisierte manuelle Buchung wird automatisch archiviert")
    expect(archived.entries.first(where: { $0.id == review.id })?.isArchived == false, "unkategorisierter CSV-Prüffall bleibt aktiv")
    let legacyEntryData = Data(#"{"id":"legacy","title":"Alt","amountCents":100,"kind":"EXPENSE","accountID":"acc","plannedDate":"2020-01-01","status":"BOOKED","isReliable":false,"affectsBalance":false}"#.utf8)
    let legacyEntry = try JSONDecoder().decode(FinanceEntry.self, from: legacyEntryData)
    expect(legacyEntry.isArchived == false, "alte Sicherungen erhalten kompatiblen Archivstatus")
}

do {
    let database = try makeDatabase()
    let snapshot = try database.snapshot()
    guard let checking = snapshot.accounts.first(where: { $0.kind == .checking }) else { throw FinanceDatabaseError.invalid("Seed-Konto fehlt.") }
    try database.addCategory(name: "Löschtest", kind: .expense, iconName: "trash")
    guard let category = try database.snapshot().categories.first(where: { $0.name == "Löschtest" }) else { throw FinanceDatabaseError.invalid("Kategorie fehlt.") }
    try database.addEntry(FinanceEntry(id: "category-linked", title: "Bleibt", amountCents: 250, kind: .expense, accountID: checking.id, categoryID: category.id, plannedDate: "2026-09-13"))
    try database.deleteCategory(id: category.id)
    let result = try database.snapshot()
    expect(!result.categories.contains(where: { $0.id == category.id }), "Kategorie lässt sich löschen")
    expect(result.entries.first(where: { $0.id == "category-linked" })?.categoryID == nil, "Buchung bleibt beim Löschen der Kategorie erhalten")
}

do {
    let csv = "Buchungstag;Buchungstext;Verwendungszweck;Betrag\n12.09.2026;Kartenzahlung;\"Markt; Berlin\";-12,34 EUR\n13.09.2026;Gutschrift;Gehalt;1.081,51 EUR\n"
    let rows = try BankCSVParser.parse(text: csv)
    expect(rows.count == 2, "deutscher CSV-Kontoauszug erkennt Soll und Haben")
    expect(rows[0].signedAmountCents == -1_234 && rows[1].signedAmountCents == 108_151, "deutsche Zahlenformate werden centgenau gelesen")
    expect(rows[0].title.contains("Markt; Berlin"), "Anführungszeichen und Trennzeichen im Verwendungszweck bleiben erhalten")

    let database = try makeDatabase()
    guard let accountID = try database.snapshot().accounts.first?.id else { throw FinanceDatabaseError.invalid("Seed-Konto fehlt.") }
    let imports = rows.map { BankImportEntry(title: $0.title, amountCents: abs($0.signedAmountCents), kind: $0.signedAmountCents >= 0 ? .income : .expense, accountID: accountID, categoryID: nil, date: $0.date, fingerprint: $0.fingerprint) }
    let firstImportCount = try database.importBankEntries(imports)
    let secondImportCount = try database.importBankEntries(imports)
    expect(firstImportCount == 2, "CSV-Buchungen werden gesammelt importiert")
    expect(secondImportCount == 0, "erneuter CSV-Import überspringt identische Duplikate")
}

do {
    let raw = "Kartenzahlung · Markt am Park · IBAN: DE02120300000000202051 · BIC BYLADEM1001 · EREF 87298374982734982734"
    let proposal = BankCSVParser.suggestedTitle(from: raw)
    expect(proposal.contains("Markt am Park"), "CSV-Titel behält den verständlichen Händler")
    expect(!proposal.contains("IBAN") && !proposal.contains("EREF") && proposal.count <= 72, "CSV-Titel entfernt SEPA-Codes und bleibt kompakt")

    let database = try makeDatabase()
    let accounts = try database.snapshot().accounts
    let source = accounts[0].id
    let target = accounts[1].id
    let transfer = BankImportEntry(title: "Sparrate", amountCents: 10_000, kind: .transfer, accountID: source, transferAccountID: target, categoryID: nil, date: "2026-09-14", fingerprint: "transfer-fingerprint")
    let firstTransferImport = try database.importBankEntries([transfer])
    let secondTransferImport = try database.importBankEntries([transfer])
    expect(firstTransferImport == 1, "CSV-Zeile kann als Umbuchung importiert werden")
    expect(secondTransferImport == 0, "CSV-Fingerprint verhindert doppelten Umbuchungsimport")
    let imported = try database.snapshot().entries.first { $0.title == "Sparrate" }
    expect(imported?.kind == .transfer && imported?.transferAccountID == target, "CSV-Umbuchung speichert Quell- und Zielkonto")
}

do {
    let database = try makeDatabase()
    let snapshot = try database.snapshot(today: "2026-09-13", days: 365)
    let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "output/pdf", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let outputURL = outputDirectory.appending(path: "Beispiel-Quartalsbericht.pdf")
    try FinanceReportGenerator.writePDF(snapshot: snapshot, startDate: "2026-07-01", endDate: "2026-09-30", accountID: nil, to: outputURL)
    let pdf = try Data(contentsOf: outputURL)
    expect(pdf.starts(with: Data("%PDF".utf8)) && pdf.count > 5_000, "Quartalsbericht wird als mehrseitige PDF-Datei erzeugt")
}

print("Kalenderperioden")

do {
    let month = CalendarPeriodEngine.period(kind: .month, containing: "2026-09-13")
    expect(month.startDate == "2026-09-01" && month.endDate == "2026-09-30", "Monat ist der vollständige Kalendermonat")
    let day = CalendarPeriodEngine.period(kind: .day, containing: "2026-09-13")
    expect(day.label.hasPrefix("So,"), "ein konkretes Datum zeigt den abgekürzten Wochentag")

    let quarter = CalendarPeriodEngine.period(kind: .quarter, containing: "2026-09-13")
    expect(quarter.startDate == "2026-07-01" && quarter.endDate == "2026-09-30", "Quartal folgt echten Kalendergrenzen (Q3)")

    let firstQuarter = CalendarPeriodEngine.period(kind: .quarter, containing: "2026-01-15")
    expect(firstQuarter.startDate == "2026-01-01" && firstQuarter.endDate == "2026-03-31", "erstes Quartal endet am 31. März")

    let half = CalendarPeriodEngine.period(kind: .halfYear, containing: "2026-09-13")
    expect(half.startDate == "2026-07-01" && half.endDate == "2026-12-31", "6-Monats-Zeitraum ist das zweite Kalenderhalbjahr")

    let year = CalendarPeriodEngine.period(kind: .year, containing: "2026-09-13")
    expect(year.startDate == "2026-01-01" && year.endDate == "2026-12-31", "Jahr ist 1. Januar bis 31. Dezember")

    let nextMonth = CalendarPeriodEngine.next(month)
    expect(nextMonth.startDate == "2026-10-01" && nextMonth.endDate == "2026-10-31", "nächster Monat navigiert korrekt weiter")
    let previousQuarter = CalendarPeriodEngine.previous(quarter)
    expect(previousQuarter.startDate == "2026-04-01" && previousQuarter.endDate == "2026-06-30", "vorheriges Quartal navigiert korrekt zurück")

    let leapMonth = CalendarPeriodEngine.period(kind: .month, containing: "2028-02-10")
    expect(leapMonth.endDate == "2028-02-29", "Schaltjahr-Februar endet am 29.")
}

do {
    let range = try CalendarPeriodEngine.custom(start: "2027-01-01", end: "2030-12-31")
    expect(range.kind == .custom && range.startDate == "2027-01-01" && range.endDate == "2030-12-31", "freier Zeitraum wird übernommen")
    expect(range.label.hasPrefix("Fr,") && range.label.contains("Di,"), "freie Datumsgrenzen zeigen ihre Wochentage")
    do {
        _ = try CalendarPeriodEngine.custom(start: "2027-05-01", end: "2027-01-01")
        expect(false, "ungültiger Zeitraum (Ende vor Start) wird abgewiesen")
    } catch {
        expect(true, "ungültiger Zeitraum (Ende vor Start) wird abgewiesen")
    }
    let nextRange = CalendarPeriodEngine.next(range)
    expect(nextRange.startDate == "2031-01-01" && nextRange.endDate == "2034-12-31", "freier Zeitraum navigiert um die eigene Länge weiter")
}

print("Betragsstufen")

do {
    let stages = [
        RecurringAmountStage(effectiveDate: "2028-09-01", adjustment: .delta(20_000)),
        RecurringAmountStage(effectiveDate: "2029-09-01", adjustment: .absolute(150_000))
    ]
    let rule = RecurringRule(id: "salary", title: "Gehalt", amountCents: 108_151, kind: .income, accountID: "checking", frequency: .monthly, startDate: "2026-09-25", schedule: .fixedDay(25), amountStages: stages)
    expect(rule.amountCents(on: "2026-09-25") == 108_151, "vor der ersten Stufe gilt der Basisbetrag")
    expect(rule.amountCents(on: "2028-08-31") == 108_151, "Basisbetrag gilt bis zum Tag vor dem Grenzdatum")
    expect(rule.amountCents(on: "2028-09-01") == 128_151, "Erhöhung um 200 Euro gilt exakt ab dem Grenzdatum")
    expect(rule.amountCents(on: "2029-08-31") == 128_151, "erhöhter Betrag bleibt bis zur nächsten Stufe stabil")
    expect(rule.amountCents(on: "2029-09-01") == 150_000, "neuer Gesamtbetrag ersetzt die vorherige Stufe exakt ab dem Grenzdatum")
    expect(rule.amountCents(on: "2031-01-01") == 150_000, "letzte Stufe bleibt danach dauerhaft gültig")

    let occurrences = FinanceEngine.occurrences(for: rule, from: "2028-08-01", through: "2028-10-01").map { ($0.plannedDate, $0.amountCents) }
    expect(occurrences.contains { $0.0 == "2028-08-25" && $0.1 == 108_151 }, "generierter Termin vor der Stufe nutzt den Basisbetrag")
    expect(occurrences.contains { $0.0 == "2028-09-25" && $0.1 == 128_151 }, "generierter Termin nach der Stufe nutzt den erhöhten Betrag")
}

print("Flexible Zahlungstermine")

do {
    let exact = RecurringRule(
        id: "exact-dates",
        title: "Unregelmäßige Zahlung",
        amountCents: 25_000,
        kind: .income,
        accountID: "checking",
        frequency: .monthly,
        startDate: "2026-09-01",
        schedule: .exactDates(["2026-09-18", "2026-12-15", "2027-03-17"])
    )
    let dates = FinanceEngine.occurrences(for: exact, from: "2026-10-01", through: "2027-01-31").map(\.plannedDate)
    expect(dates == ["2026-12-15"], "individuelle Termine werden exakt und nur im gewählten Zeitraum erzeugt")
}

do {
    let window = RecurringRule(id: "child", title: "Kindergeld", amountCents: 25_900, kind: .income, accountID: "checking", frequency: .monthly, startDate: "2026-09-01", schedule: .dateWindow(startDay: 15, endDay: 25))
    let incomeDates = FinanceEngine.occurrences(for: window, from: "2026-09-01", through: "2026-11-30").map(\.plannedDate)
    expect(incomeDates == ["2026-09-25", "2026-10-25", "2026-11-25"], "Einnahmen im Datumsfenster werden konservativ am spätesten Tag angesetzt")

    let expenseWindow = RecurringRule(id: "rent-window", title: "Miete", amountCents: 82_000, kind: .expense, accountID: "checking", frequency: .monthly, startDate: "2026-09-01", schedule: .dateWindow(startDay: 15, endDay: 25))
    let expenseDates = FinanceEngine.occurrences(for: expenseWindow, from: "2026-09-01", through: "2026-11-30").map(\.plannedDate)
    expect(expenseDates == ["2026-09-15", "2026-10-15", "2026-11-15"], "Ausgaben im Datumsfenster werden konservativ am frühesten Tag angesetzt")
}

do {
    // Letzter Mittwoch am oder vor dem 28. eines Monats.
    let rule = RecurringRule(id: "weekday-rule", title: "Auszahlung", amountCents: 10_000, kind: .income, accountID: "checking", frequency: .monthly, startDate: "2026-09-01", schedule: .weekdayBeforeDeadline(weekday: 4, deadlineDay: 28))
    let dates = FinanceEngine.occurrences(for: rule, from: "2026-09-01", through: "2026-11-30").map(\.plannedDate)
    // September 2026: 28. ist ein Montag -> letzter Mittwoch am/vor dem 28. ist der 23.
    expect(dates.contains("2026-09-23"), "letzter Mittwoch am oder vor dem 28. September wird korrekt gefunden")
    // Oktober 2026: 28. ist ein Mittwoch selbst.
    expect(dates.contains("2026-10-28"), "fällt der Stichtag selbst auf den Wochentag, wird er verwendet")

    var excluded = rule
    excluded.excludedDates = ["2026-10-28"]
    let adjustedDates = FinanceEngine.occurrences(for: excluded, from: "2026-09-01", through: "2026-11-30").map(\.plannedDate)
    expect(adjustedDates.contains("2026-10-21") && !adjustedDates.contains("2026-10-28"), "ausgeschlossener Mittwoch weicht auf den vorherigen gültigen Mittwoch aus")
}

print("Demnächst-Liste und historische Verläufe")

do {
    let account = makeAccount(balance: 90_000)
    let futureBooked = FinanceEntry(id: "future-booked", title: "Bereits vorgemerkt", amountCents: 10_000, kind: .expense, accountID: account.id, plannedDate: "2026-09-20", actualDate: "2026-09-20", status: .booked, affectsBalance: true)
    let timeline = FinanceEngine.timeline(accounts: [account], entries: [futureBooked], rules: [], today: "2026-09-15", start: "2026-09-15", end: "2026-09-21")
    expect(timeline.first?.balanceCents == 100_000, "zukünftig gebuchte Ausgabe wird aus dem heutigen Diagrammanker zurückgerechnet")
    expect(timeline.first { $0.date == "2026-09-20" }?.balanceCents == 90_000, "zukünftig gebuchte Ausgabe wirkt im Diagramm genau einmal am Buchungstag")
}

do {
    let database = try makeDatabase()
    let checking = try database.snapshot().accounts.first { $0.kind == .checking }!
    let booked = FinanceEntry(id: "past-1", title: "Alteinkauf", amountCents: 5_000, kind: .expense, accountID: checking.id, plannedDate: "2026-08-20", actualDate: "2026-08-20", status: .booked, affectsBalance: true)
    try database.addEntry(booked)
    let startBalance = try database.snapshot().accounts.first { $0.id == checking.id }!.currentBalanceCents

    let historical = try database.timeline(from: "2026-08-15", through: "2026-08-25", today: "2026-09-13")
    let before = historical.first { $0.accountID == checking.id && $0.date == "2026-08-19" }?.balanceCents
    let after = historical.first { $0.accountID == checking.id && $0.date == "2026-08-20" }?.balanceCents
    expect(before == startBalance + 5_000, "Saldo vor der historischen Buchung wird korrekt zurückgerechnet")
    expect(after == startBalance, "Saldo am Buchungstag entspricht dem heutigen Saldo abzüglich nichts Weiteres")

    let planned = FinanceEntry(id: "upcoming-1", title: "Geplante Ausgabe", amountCents: 3_000, kind: .expense, accountID: checking.id, plannedDate: "2026-09-20", status: .planned)
    try database.addEntry(planned)
    let upcoming = try database.occurrencesAndEntries(from: "2026-09-01", through: "2026-09-30", today: "2026-09-13")
    expect(upcoming.contains { $0.id == "upcoming-1" }, "Demnächst-Liste enthält geplante Buchungen im gewählten Zeitraum")
    expect(!upcoming.contains { $0.id == "past-1" }, "Demnächst-Liste bleibt auf den gewählten Zeitraum begrenzt")
}

print("Sicherungs-Roundtrip mit Betragsstufen und flexiblen Terminen")

do {
    let database = try makeDatabase()
    let checking = try database.snapshot().accounts.first { $0.kind == .checking }!
    let rule = RecurringRule(
        id: "roundtrip-rule",
        title: "Gehalt mit Stufen",
        amountCents: 100_000,
        kind: .income,
        accountID: checking.id,
        frequency: .monthly,
        startDate: "2026-09-01",
        schedule: .weekdayBeforeDeadline(weekday: 4, deadlineDay: 28),
        amountStages: [RecurringAmountStage(effectiveDate: "2028-09-01", adjustment: .delta(20_000))],
        excludedDates: ["2026-10-28"]
    )
    try database.addRecurringRule(rule)
    let exportURL = FileManager.default.temporaryDirectory.appending(path: "finanzplan-schedule-backup-\(UUID().uuidString).json")
    try database.exportData(to: exportURL)

    let restoredDatabase = try makeDatabase()
    _ = try restoredDatabase.importData(from: exportURL)
    let restoredRule = try restoredDatabase.snapshot().rules.first { $0.id == "roundtrip-rule" }
    expect(restoredRule?.schedule == .weekdayBeforeDeadline(weekday: 4, deadlineDay: 28), "Terminart übersteht Sicherungs-Roundtrip")
    expect(restoredRule?.excludedDates == ["2026-10-28"], "Ausnahmetermine überstehen Sicherungs-Roundtrip")
    expect(restoredRule?.amountCents(on: "2028-09-01") == 120_000, "Betragsstufen überstehen Sicherungs-Roundtrip")

    let legacyRuleData = Data(#"{"id":"legacy-rule","title":"Alt","amountCents":5000,"kind":"EXPENSE","accountID":"acc","frequency":"MONTHLY","interval":1,"startDate":"2020-01-01","dueDay":15,"isReliable":false,"isActive":true,"needsReview":false}"#.utf8)
    let legacyRule = try JSONDecoder().decode(RecurringRule.self, from: legacyRuleData)
    expect(legacyRule.schedule == .fixedDay(15), "alte Sicherung ohne Terminart wird auf festen Kalendertag abgebildet")
    expect(legacyRule.amountStages.isEmpty && legacyRule.excludedDates.isEmpty, "alte Sicherung erhält leere Betragsstufen und Ausnahmen")
}

print("Duplikat-Erkennung beim Import")

func importCandidate(_ title: String, cents: Int = 1_234, date: String = "2026-09-12", account: String = "acc", kind: EntryKind = .expense, transfer: String? = nil, fingerprint: String? = nil) -> BankImportEntry {
    BankImportEntry(title: title, amountCents: cents, kind: kind, accountID: account, transferAccountID: transfer, categoryID: nil, date: date, fingerprint: fingerprint)
}

func storedEntry(_ id: String, title: String, cents: Int = 1_234, date: String = "2026-09-12", account: String = "acc", kind: EntryKind = .expense, status: EntryStatus = .booked, transfer: String? = nil) -> FinanceEntry {
    FinanceEntry(id: id, title: title, amountCents: cents, kind: kind, accountID: account, transferAccountID: transfer, plannedDate: date, actualDate: status == .booked ? date : nil, status: status)
}

do {
    expect(TextNormalizer.normalized("  Müller-Straße  #12 ") == "muller strasse 12", "Textnormalisierung faltet Umlaute, Satzzeichen und Leerzeichen")

    let exact = ImportDuplicateDetector.detect([importCandidate("Kartenzahlung Markt am Park Berlin")], existing: [storedEntry("a", title: "Markt am Park")])
    expect(exact[0]?.level == .certain && exact[0]?.entryID == "a", "gleicher Betrag, Tag und enthaltener Text ist ein sicheres Duplikat")

    let twoAgainstOne = ImportDuplicateDetector.detect([importCandidate("Kaffee"), importCandidate("Kaffee")], existing: [storedEntry("a", title: "Kaffee")])
    expect(twoAgainstOne[0]?.level == .certain && twoAgainstOne[1] == nil, "zwei identische Zeilen gegen eine Buchung ergeben ein Duplikat und eine neue Zeile")

    let noStored = ImportDuplicateDetector.detect([importCandidate("Kaffee"), importCandidate("Kaffee")], existing: [])
    expect(noStored.allSatisfy { $0 == nil }, "ohne Bestand ist keine Zeile ein Duplikat")

    let shifted = ImportDuplicateDetector.detect([importCandidate("Kaffee")], existing: [storedEntry("a", title: "Kaffee", date: "2026-09-13")])
    expect(shifted[0]?.level == .possible, "Datum einen Tag versetzt ist ein mögliches Duplikat")
    let tooFar = ImportDuplicateDetector.detect([importCandidate("Kaffee")], existing: [storedEntry("a", title: "Kaffee", date: "2026-09-16")])
    expect(tooFar[0] == nil, "Datum über der Toleranz ist kein Duplikat")

    let otherAccount = ImportDuplicateDetector.detect([importCandidate("Kaffee", account: "other")], existing: [storedEntry("a", title: "Kaffee")])
    expect(otherAccount[0] == nil, "anderes Konto ist kein Duplikat")
    let otherKind = ImportDuplicateDetector.detect([importCandidate("Kaffee", kind: .income)], existing: [storedEntry("a", title: "Kaffee")])
    expect(otherKind[0] == nil, "Einnahme und Ausgabe gleichen Betrags sind keine Duplikate")

    let cancelled = ImportDuplicateDetector.detect([importCandidate("Kaffee")], existing: [storedEntry("a", title: "Kaffee", status: .cancelled)])
    expect(cancelled[0] == nil, "stornierte Buchungen werden ignoriert")
    let planned = ImportDuplicateDetector.detect([importCandidate("Kaffee")], existing: [storedEntry("a", title: "Kaffee", status: .planned)])
    expect(planned[0]?.level == .possible, "geplante Buchung gleichen Betrags ist nur ein mögliches Duplikat")
    let otherText = ImportDuplicateDetector.detect([importCandidate("Supermarkt")], existing: [storedEntry("a", title: "Kaffee")])
    expect(otherText[0]?.level == .possible, "gleicher Tag und Betrag mit anderem Text ist ein mögliches Duplikat")

    let transfer = ImportDuplicateDetector.detect([importCandidate("Sparrate", kind: .transfer, transfer: "sav")], existing: [storedEntry("a", title: "Sparrate", kind: .transfer, transfer: "sav")])
    expect(transfer[0]?.level == .certain, "Umbuchung mit gleichem Kontopaar ist ein Duplikat")
    let reversed = ImportDuplicateDetector.detect([importCandidate("Sparrate", kind: .transfer, transfer: "sav")], existing: [storedEntry("a", title: "Sparrate", account: "sav", kind: .transfer, transfer: "acc")])
    expect(reversed[0] == nil, "Umbuchung mit vertauschtem Kontopaar ist kein Duplikat")

    let known = ImportDuplicateDetector.detect([importCandidate("Kaffee", fingerprint: "abc")], existing: [], knownFingerprints: ["abc"])
    expect(known[0]?.level == .certain && known[0]?.entryID == nil, "bekannter Import-Fingerprint ist ein sicheres Duplikat")

    let mixed = ImportDuplicateDetector.detect(
        [importCandidate("Anderes"), importCandidate("Markt")],
        existing: [storedEntry("a", title: "Markt"), storedEntry("b", title: "Sonstiges", date: "2026-09-13")]
    )
    expect(mixed[1]?.level == .certain && mixed[1]?.entryID == "a" && mixed[0]?.level == .possible && mixed[0]?.entryID == "b", "sichere Treffer haben Vorrang vor möglichen")
}

do {
    let csv = "Buchungstag;Verwendungszweck;Betrag\n12.09.2026;Kaffee;-3,50\n12.09.2026;Kaffee;-3,50\n"
    let rows = try BankCSVParser.parse(text: csv)
    expect(rows.count == 2 && rows[0].fingerprint != rows[1].fingerprint, "identische Zeilen einer Datei erhalten verschiedene Fingerprints")
    expect(rows[0].fingerprint == BankCSVParser.fingerprint(for: "2026-09-12|-350|Kaffee"), "erste Zeile behält den bisherigen Fingerprint")

    let database = try makeDatabase()
    guard let accountID = try database.snapshot().accounts.first?.id else { throw FinanceDatabaseError.invalid("Seed-Konto fehlt.") }
    let imports = rows.map { BankImportEntry(title: $0.title, amountCents: abs($0.signedAmountCents), kind: .expense, accountID: accountID, categoryID: nil, date: $0.date, fingerprint: $0.fingerprint) }
    let firstImport = try database.importBankEntries(imports)
    let secondImport = try database.importBankEntries(imports)
    expect(firstImport == 2, "zwei gleiche Käufe am selben Tag werden beide importiert")
    expect(secondImport == 0, "erneuter Import überspringt beide")

    let exportURL = FileManager.default.temporaryDirectory.appending(path: "finanzplan-fingerprints-\(UUID().uuidString).json")
    try database.exportData(to: exportURL)
    let restored = try makeDatabase()
    _ = try restored.importData(from: exportURL)
    let restoredFingerprints = try restored.bankImportFingerprints()
    let reimportAfterRestore = try restored.importBankEntries(imports)
    expect(restoredFingerprints == Set(rows.map(\.fingerprint)), "Import-Fingerprints überstehen den Sicherungs-Roundtrip")
    expect(reimportAfterRestore == 0, "nach der Wiederherstellung erkennt der Import bekannte Zeilen")

    guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as? [String: Any] else { throw FinanceDatabaseError.invalid("Sicherung nicht lesbar.") }
    object.removeValue(forKey: "bankImportRecords")
    let legacyURL = FileManager.default.temporaryDirectory.appending(path: "finanzplan-legacy-\(UUID().uuidString).json")
    try JSONSerialization.data(withJSONObject: object).write(to: legacyURL)
    let legacyRestore = try makeDatabase()
    _ = try legacyRestore.importData(from: legacyURL)
    let legacyFingerprints = try legacyRestore.bankImportFingerprints()
    let legacyEntryCount = try legacyRestore.snapshot().entries.count
    let originalEntryCount = try database.snapshot().entries.count
    expect(legacyFingerprints.isEmpty && legacyEntryCount == originalEntryCount, "alte Sicherung ohne Fingerprints bleibt importierbar")
}

print("Belege")

func makeIsolatedDatabase() throws -> (FinanceDatabase, URL) {
    let folder = FileManager.default.temporaryDirectory.appending(path: "finanzplan-verify-\(UUID().uuidString)", directoryHint: .isDirectory)
    return (try FinanceDatabase(fileURL: folder.appending(path: "finanzplan.sqlite")), folder)
}

func makeReceipt(in folder: URL, name: String, data: Data) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: name)
    try data.write(to: url)
    return url
}

do {
    let (database, folder) = try makeIsolatedDatabase()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sources = folder.appending(path: "quellen", directoryHint: .isDirectory)
    guard let accountID = try database.snapshot().accounts.first?.id else { throw FinanceDatabaseError.invalid("Seed-Konto fehlt.") }
    try database.addEntry(storedEntry("att-1", title: "Rechnung", account: accountID))
    try database.addEntry(storedEntry("att-2", title: "Zweitbuchung", account: accountID))
    let store = database.attachmentStore

    let pdf = try makeReceipt(in: sources, name: "Rechnung.pdf", data: Data("%PDF-1.4 synthetischer Beleg".utf8))
    let added = try database.addAttachments(entryID: "att-1", sources: [pdf])
    expect(added.count == 1 && store.fileExists(storedName: added[0].storedName), "Beleg wird in den Belege-Ordner kopiert und erfasst")
    expect(added[0].storedName.count == 64 + 4 && AttachmentStore.isValidStoredName(added[0].storedName), "Beleg wird unter seinem SHA-256 gespeichert")
    let counts = try database.attachmentCounts()
    expect(counts["att-1"] == 1 && counts["att-2"] == nil, "Beleganzahl wird pro Buchung gezählt")

    let sharedSecond = try database.addAttachments(entryID: "att-2", sources: [pdf])
    expect(sharedSecond.first?.storedName == added[0].storedName, "identische Belege teilen sich eine Datei")
    let repeated = try database.addAttachments(entryID: "att-1", sources: [pdf])
    expect(repeated.isEmpty, "derselbe Beleg wird an einer Buchung nicht doppelt erfasst")

    try database.deleteEntry(id: "att-1")
    expect(store.fileExists(storedName: added[0].storedName), "Datei bleibt, solange eine andere Buchung sie nutzt")
    try database.deleteEntry(id: "att-2")
    expect(!store.fileExists(storedName: added[0].storedName), "Datei wird mit der letzten Buchung entfernt")

    let fake = try makeReceipt(in: sources, name: "Falsch.pdf", data: Data("kein pdf".utf8))
    let script = try makeReceipt(in: sources, name: "programm.sh", data: Data("#!/bin/sh".utf8))
    let huge = try makeReceipt(in: sources, name: "Gross.pdf", data: Data("%PDF".utf8) + Data(count: AttachmentStore.maximumFileSize))
    for (label, url) in [("falsche Signatur", fake), ("nicht erlaubter Typ", script), ("zu große Datei", huge)] {
        var rejected = false
        do { _ = try AttachmentStore.validate(url) } catch { rejected = true }
        expect(rejected, "Beleg wird abgelehnt: \(label)")
    }

    try database.addEntry(storedEntry("att-3", title: "Fehlerfall", account: accountID))
    let good = try makeReceipt(in: sources, name: "Gut.pdf", data: Data("%PDF-1.7 anderer Beleg".utf8))
    var rolledBack = false
    do { _ = try database.addAttachments(entryID: "att-3", sources: [good, fake]) } catch { rolledBack = true }
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
    let remainingCount = try database.attachments(entryID: "att-3").count
    expect(rolledBack && remainingCount == 0 && leftovers.isEmpty, "fehlgeschlagener Anhang-Vorgang hinterlässt keine Dateien")
}

do {
    let (database, folder) = try makeIsolatedDatabase()
    let (restoredDatabase, restoredFolder) = try makeIsolatedDatabase()
    defer {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: restoredFolder)
    }
    guard let accountID = try database.snapshot().accounts.first?.id else { throw FinanceDatabaseError.invalid("Seed-Konto fehlt.") }
    try database.addEntry(storedEntry("att-backup", title: "Mit Beleg", account: accountID))
    let png = try makeReceipt(in: folder.appending(path: "quellen", directoryHint: .isDirectory), name: "Foto.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01]))
    let added = try database.addAttachments(entryID: "att-backup", sources: [png])
    let backupURL = folder.appending(path: "sicherung.json")
    try database.exportData(to: backupURL)

    _ = try restoredDatabase.importData(from: backupURL)
    let restoredAttachments = try restoredDatabase.attachments(entryID: "att-backup")
    let missing = try restoredDatabase.missingAttachmentFileCount()
    expect(restoredAttachments.map(\.storedName) == added.map(\.storedName) && restoredAttachments.first?.fileName == "Foto.png", "Beleg-Angaben überstehen den Sicherungs-Roundtrip")
    expect(missing == 1, "fehlende Belegdateien nach der Wiederherstellung werden gezählt")
    let sameMachineMissing = try database.missingAttachmentFileCount()
    expect(sameMachineMissing == 0, "vorhandene Belegdateien gelten nicht als fehlend")

    guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: backupURL)) as? [String: Any],
          var attachments = object["attachments"] as? [[String: Any]] else { throw FinanceDatabaseError.invalid("Sicherung nicht lesbar.") }
    attachments[0]["storedName"] = "../../evil.pdf"
    object["attachments"] = attachments
    let evilURL = folder.appending(path: "boese.json")
    try JSONSerialization.data(withJSONObject: object).write(to: evilURL)
    var rejected = false
    do { _ = try makeDatabase().importData(from: evilURL) } catch { rejected = true }
    expect(rejected, "Sicherung mit Pfadangabe im Belegnamen wird abgelehnt")

    object.removeValue(forKey: "attachments")
    let legacyURL = folder.appending(path: "alt.json")
    try JSONSerialization.data(withJSONObject: object).write(to: legacyURL)
    let legacyDatabase = try makeDatabase()
    _ = try legacyDatabase.importData(from: legacyURL)
    let legacyCounts = try legacyDatabase.attachmentCounts()
    expect(legacyCounts.isEmpty, "alte Sicherung ohne Belege bleibt importierbar")
}

print("Menüleisten-Zusammenfassung")

do {
    let items = [
        storedEntry("open-late", title: "Miete", date: "2026-09-25", status: .planned),
        storedEntry("open-early", title: "Telefon", date: "2026-09-20", status: .planned),
        storedEntry("done", title: "Erledigt", date: "2026-09-20", status: .booked),
        storedEntry("cancelled", title: "Storniert", date: "2026-09-19", status: .cancelled),
        storedEntry("past", title: "Vergangen", date: "2026-09-10", status: .planned),
        storedEntry("far", title: "Später", date: "2026-10-30", status: .planned),
        storedEntry("today", title: "Heute", date: "2026-09-18", status: .planned)
    ]
    let upcoming = UpcomingSummary.entries(in: items, today: "2026-09-18", days: 14, limit: 5)
    expect(upcoming.map(\.id) == ["today", "open-early", "open-late"], "nächste Buchungen sind offen, im Zeitfenster und chronologisch")
    let limited = UpcomingSummary.entries(in: items, today: "2026-09-18", days: 14, limit: 2)
    expect(limited.map(\.id) == ["today", "open-early"], "Limit begrenzt die Liste auf die frühesten Buchungen")
}

print("")
print("\(checks) Prüfungen, \(failures) Fehler")
if failures > 0 {
    exit(1)
}
