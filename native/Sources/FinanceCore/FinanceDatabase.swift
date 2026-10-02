import Foundation
import SQLite3

public enum FinanceDatabaseError: Error, LocalizedError {
    case open(String)
    case statement(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message): "Datenbank konnte nicht geöffnet werden: \(message)"
        case .statement(let message): "Datenbankfehler: \(message)"
        case .invalid(let message): message
        }
    }
}

public final class FinanceDatabase {
    public let fileURL: URL
    private let connection: OpaquePointer

    public init(fileURL: URL? = nil) throws {
        let resolvedURL = try fileURL ?? Self.defaultFileURL()
        try FileManager.default.createDirectory(at: resolvedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(resolvedURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unbekannter Fehler"
            if let database { sqlite3_close(database) }
            throw FinanceDatabaseError.open(message)
        }
        self.fileURL = resolvedURL
        connection = database
        try execute("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA temp_store = MEMORY;")
        try createSchema()
        try migrateSchema()
        try seedIfNeeded()
    }

    deinit {
        sqlite3_close(connection)
    }

    public func snapshot(today: String = FinanceCalendar.today(), days: Int = 90) throws -> FinanceSnapshot {
        try archiveOldManualEntries(today: today)
        let accounts = try accounts()
        let categories = try categories()
        let entries = try entries()
        let rules = try recurringRules()
        let engine = FinanceEngine.snapshot(accounts: accounts, entries: entries, rules: rules, today: today, days: min(365, max(30, days)))
        let budgets = try budgets(month: String(today.prefix(7)), entries: entries)
        return FinanceSnapshot(today: today, accounts: accounts, categories: categories, entries: entries, occurrences: engine.occurrences, rules: rules, budgets: budgets, liquidity: engine.liquidity, forecast: engine.forecast)
    }

    /// Account balances across an arbitrary calendar range, including history
    /// before today. Used by the dashboard chart so it can navigate to past
    /// and future calendar periods without recomputing the full snapshot.
    public func timeline(from start: String, through end: String, today: String = FinanceCalendar.today()) throws -> [ForecastPoint] {
        FinanceEngine.timeline(accounts: try accounts(), entries: try entries(), rules: try recurringRules(), today: today, start: start, end: end)
    }

    /// Materialized entries plus generated future occurrences within an
    /// arbitrary calendar range, chronologically sorted. Backs the
    /// "Demnächst" list so it always matches the chart's active period.
    public func occurrencesAndEntries(from start: String, through end: String, today: String = FinanceCalendar.today()) throws -> [FinanceEntry] {
        FinanceEngine.occurrencesAndEntries(entries: try entries(), rules: try recurringRules(), today: today, start: start, end: end)
    }

    public func updateAccount(_ account: Account) throws {
        guard !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FinanceDatabaseError.invalid("Der Kontoname fehlt.") }
        try transaction {
            if account.isPrimary {
                try run("UPDATE accounts SET is_primary = 0")
            }
            try run(
                "UPDATE accounts SET name = ?, kind = ?, balance_cents = ?, balance_as_of = ?, buffer_cents = ?, color_hex = ?, is_primary = ?, needs_review = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                [.text(account.name), .text(account.kind.rawValue), .integer(account.currentBalanceCents), .text(account.balanceAsOf), .integer(max(0, account.minimumBufferCents)), .text(account.colorHex), .integer(account.isPrimary ? 1 : 0), .text(account.id)]
            )
        }
    }

    /// Confirms that the currently calculated account balance was checked on
    /// the supplied date. The amount itself is not altered.
    public func confirmAccountBalance(id: String, date: String) throws {
        try run(
            "UPDATE accounts SET balance_as_of = ?, needs_review = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            [.text(date), .text(id)]
        )
    }

    public func addAccount(name: String, kind: AccountKind, balanceCents: Int, bufferCents: Int, colorHex: String = "#4C8D79", isPrimary: Bool) throws {
        let id = UUID().uuidString
        let today = FinanceCalendar.today()
        if isPrimary { try run("UPDATE accounts SET is_primary = 0") }
        try run(
            "INSERT INTO accounts (id, name, kind, balance_cents, balance_as_of, buffer_cents, color_hex, is_primary, needs_review) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)",
            [.text(id), .text(name), .text(kind.rawValue), .integer(balanceCents), .text(today), .integer(max(0, bufferCents)), .text(colorHex), .integer(isPrimary ? 1 : 0)]
        )
    }

    public func deleteAccount(id: String) throws {
        let allAccounts = try accounts()
        guard let account = allAccounts.first(where: { $0.id == id }) else { return }
        guard allAccounts.count > 1 else {
            throw FinanceDatabaseError.invalid("Das letzte Konto kann nicht gelöscht werden.")
        }

        let linkedRuleIDs = Set(try recurringRules().filter {
            $0.accountID == id || $0.transferAccountID == id
        }.map(\.id))
        let linkedEntries = try entries().filter {
            $0.accountID == id || $0.transferAccountID == id || ($0.recurrenceID.map(linkedRuleIDs.contains) ?? false)
        }
        let storedNames = try storedAttachmentNames(forEntryIDs: linkedEntries.map(\.id))

        try transaction {
            for entry in linkedEntries where entry.status == .booked && entry.affectsBalance {
                try applyBalanceEffect(for: entry, direction: -1)
            }
            try run(
                "DELETE FROM entries WHERE account_id = ? OR transfer_account_id = ? OR recurrence_id IN (SELECT id FROM recurring_rules WHERE account_id = ? OR transfer_account_id = ?)",
                [.text(id), .text(id), .text(id), .text(id)]
            )
            try run("DELETE FROM recurring_rules WHERE account_id = ? OR transfer_account_id = ?", [.text(id), .text(id)])
            try run("DELETE FROM accounts WHERE id = ?", [.text(id)])
            if account.isPrimary {
                try run("UPDATE accounts SET is_primary = 1 WHERE id = (SELECT id FROM accounts ORDER BY name LIMIT 1)")
            }
        }
        try removeUnreferencedFiles(storedNames)
    }

    public func addEntry(_ entry: FinanceEntry) throws {
        guard entry.amountCents > 0 else { throw FinanceDatabaseError.invalid("Der Betrag muss größer als null sein.") }
        if entry.kind == .transfer, entry.transferAccountID == nil || entry.transferAccountID == entry.accountID {
            throw FinanceDatabaseError.invalid("Quell- und Zielkonto müssen verschieden sein.")
        }
        try transaction {
            try run(
                "INSERT INTO entries (id, title, amount_cents, kind, account_id, transfer_account_id, category_id, recurrence_id, planned_date, actual_date, status, note, is_reliable, affects_balance, is_archived) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [.text(entry.id), .text(entry.title), .integer(entry.amountCents), .text(entry.kind.rawValue), .text(entry.accountID), .optionalText(entry.transferAccountID), .optionalText(entry.categoryID), .optionalText(entry.recurrenceID), .text(entry.plannedDate), .optionalText(entry.actualDate), .text(entry.status.rawValue), .optionalText(entry.note), .integer(entry.isReliable ? 1 : 0), .integer(entry.affectsBalance ? 1 : 0), .integer(entry.isArchived ? 1 : 0)]
            )
            if entry.status == .booked, entry.affectsBalance { try applyBalanceEffect(for: entry, direction: 1) }
        }
    }

    public func deleteEntry(id: String) throws {
        guard let existing = try entry(id: id) else { return }
        let storedNames = try storedAttachmentNames(forEntryIDs: [id])
        try transaction {
            if existing.status == .booked, existing.affectsBalance { try applyBalanceEffect(for: existing, direction: -1) }
            try run("DELETE FROM entries WHERE id = ?", [.text(id)])
        }
        try removeUnreferencedFiles(storedNames)
    }

    // MARK: Attachments

    public var attachmentStore: AttachmentStore {
        AttachmentStore(directory: fileURL.deletingLastPathComponent().appending(path: "Belege", directoryHint: .isDirectory))
    }

    public func attachments(entryID: String) throws -> [EntryAttachment] {
        try query(
            "SELECT id,entry_id,file_name,stored_name,size_bytes,sha256,created_at FROM entry_attachments WHERE entry_id = ? ORDER BY created_at,file_name",
            [.text(entryID)]
        ) { statement in attachment(from: statement) }
    }

    public func attachmentCounts() throws -> [String: Int] {
        Dictionary(uniqueKeysWithValues: try query("SELECT entry_id, COUNT(*) FROM entry_attachments GROUP BY entry_id") { statement in
            (text(statement, 0), integer(statement, 1))
        })
    }

    /// Copies each file into the receipt folder, then records it. Files that
    /// were copied for a call that fails are removed again.
    @discardableResult
    public func addAttachments(entryID: String, sources: [URL]) throws -> [EntryAttachment] {
        guard try entry(id: entryID) != nil else { throw FinanceDatabaseError.invalid("Die Buchung wurde nicht gefunden.") }
        let store = attachmentStore
        var stored: [AttachmentStore.StoredFile] = []
        do {
            for source in sources { stored.append(try store.importFile(at: source)) }
            let known = Set(try attachments(entryID: entryID).map(\.sha256))
            var seen = known
            var added: [EntryAttachment] = []
            try transaction {
                for file in stored where seen.insert(file.sha256).inserted {
                    let record = EntryAttachment(entryID: entryID, fileName: file.fileName, storedName: file.storedName, sizeBytes: file.sizeBytes, sha256: file.sha256)
                    try run(
                        "INSERT INTO entry_attachments (id,entry_id,file_name,stored_name,size_bytes,sha256) VALUES (?,?,?,?,?,?)",
                        [.text(record.id), .text(record.entryID), .text(record.fileName), .text(record.storedName), .integer(record.sizeBytes), .text(record.sha256)]
                    )
                    added.append(record)
                }
            }
            return added
        } catch {
            for file in stored where file.wasCreated { store.remove(storedName: file.storedName) }
            throw error
        }
    }

    public func removeAttachment(id: String) throws {
        let names = try query("SELECT stored_name FROM entry_attachments WHERE id = ?", [.text(id)]) { statement in text(statement, 0) }
        try run("DELETE FROM entry_attachments WHERE id = ?", [.text(id)])
        try removeUnreferencedFiles(Set(names))
    }

    /// Number of attachment rows whose file is no longer in the receipt folder,
    /// for example after restoring a backup on another Mac.
    public func missingAttachmentFileCount() throws -> Int {
        let store = attachmentStore
        return try query("SELECT DISTINCT stored_name FROM entry_attachments") { statement in text(statement, 0) }
            .filter { !store.fileExists(storedName: $0) }
            .count
    }

    private func allAttachments() throws -> [EntryAttachment] {
        try query("SELECT id,entry_id,file_name,stored_name,size_bytes,sha256,created_at FROM entry_attachments ORDER BY entry_id,created_at,id") { statement in
            attachment(from: statement)
        }
    }

    private func attachment(from statement: OpaquePointer) -> EntryAttachment {
        EntryAttachment(id: text(statement, 0), entryID: text(statement, 1), fileName: text(statement, 2), storedName: text(statement, 3), sizeBytes: integer(statement, 4), sha256: text(statement, 5), createdAt: text(statement, 6))
    }

    private func storedAttachmentNames(forEntryIDs ids: [String]) throws -> Set<String> {
        var names = Set<String>()
        for id in ids {
            names.formUnion(try query("SELECT stored_name FROM entry_attachments WHERE entry_id = ?", [.text(id)]) { statement in text(statement, 0) })
        }
        return names
    }

    private func removeUnreferencedFiles(_ storedNames: Set<String>) throws {
        let store = attachmentStore
        for name in storedNames where try scalarInt("SELECT COUNT(*) FROM entry_attachments WHERE stored_name = ?", [.text(name)]) == 0 {
            store.remove(storedName: name)
        }
    }

    public func updateEntry(_ entry: FinanceEntry) throws {
        guard entry.amountCents > 0 else { throw FinanceDatabaseError.invalid("Der Betrag muss größer als null sein.") }
        if entry.kind == .transfer, entry.transferAccountID == nil || entry.transferAccountID == entry.accountID {
            throw FinanceDatabaseError.invalid("Quell- und Zielkonto müssen verschieden sein.")
        }
        guard let existing = try self.entry(id: entry.id) else {
            throw FinanceDatabaseError.invalid("Die Buchung wurde nicht gefunden.")
        }
        try transaction {
            if existing.status == .booked, existing.affectsBalance { try applyBalanceEffect(for: existing, direction: -1) }
            try run(
                "UPDATE entries SET title = ?, amount_cents = ?, kind = ?, account_id = ?, transfer_account_id = ?, category_id = ?, recurrence_id = ?, planned_date = ?, actual_date = ?, status = ?, note = ?, is_reliable = ?, affects_balance = ?, is_archived = ? WHERE id = ?",
                [.text(entry.title), .integer(entry.amountCents), .text(entry.kind.rawValue), .text(entry.accountID), .optionalText(entry.transferAccountID), .optionalText(entry.categoryID), .optionalText(entry.recurrenceID), .text(entry.plannedDate), .optionalText(entry.actualDate), .text(entry.status.rawValue), .optionalText(entry.note), .integer(entry.isReliable ? 1 : 0), .integer(entry.affectsBalance ? 1 : 0), .integer(entry.isArchived ? 1 : 0), .text(entry.id)]
            )
            if entry.status == .booked, entry.affectsBalance { try applyBalanceEffect(for: entry, direction: 1) }
        }
    }

    public func addRecurringRule(_ rule: RecurringRule) throws {
        guard rule.amountCents > 0 else { throw FinanceDatabaseError.invalid("Der Betrag muss größer als null sein.") }
        try validateStages(rule.amountStages)
        try run(
            "INSERT INTO recurring_rules (id, title, amount_cents, kind, account_id, transfer_account_id, category_id, frequency, interval_count, start_date, end_date, due_day, schedule_json, amount_stages_json, excluded_dates_json, is_reliable, is_active, needs_review) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [.text(rule.id), .text(rule.title), .integer(rule.amountCents), .text(rule.kind.rawValue), .text(rule.accountID), .optionalText(rule.transferAccountID), .optionalText(rule.categoryID), .text(rule.frequency.rawValue), .integer(max(1, rule.interval)), .text(rule.startDate), .optionalText(rule.endDate), .optionalInteger(rule.dueDay), .text(encodeJSON(rule.schedule)), .text(encodeJSON(rule.amountStages)), .text(encodeJSON(rule.excludedDates)), .integer(rule.isReliable ? 1 : 0), .integer(rule.isActive ? 1 : 0), .integer(rule.needsReview ? 1 : 0)]
        )
    }

    public func updateRecurringRule(_ rule: RecurringRule) throws {
        guard rule.amountCents > 0 else { throw FinanceDatabaseError.invalid("Der Betrag muss größer als null sein.") }
        if rule.kind == .transfer, rule.transferAccountID == nil || rule.transferAccountID == rule.accountID {
            throw FinanceDatabaseError.invalid("Quell- und Zielkonto müssen verschieden sein.")
        }
        try validateStages(rule.amountStages)
        try run(
            "UPDATE recurring_rules SET title = ?, amount_cents = ?, kind = ?, account_id = ?, transfer_account_id = ?, category_id = ?, frequency = ?, interval_count = ?, start_date = ?, end_date = ?, due_day = ?, schedule_json = ?, amount_stages_json = ?, excluded_dates_json = ?, is_reliable = ?, is_active = ?, needs_review = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            [.text(rule.title), .integer(rule.amountCents), .text(rule.kind.rawValue), .text(rule.accountID), .optionalText(rule.transferAccountID), .optionalText(rule.categoryID), .text(rule.frequency.rawValue), .integer(max(1, rule.interval)), .text(rule.startDate), .optionalText(rule.endDate), .optionalInteger(rule.dueDay), .text(encodeJSON(rule.schedule)), .text(encodeJSON(rule.amountStages)), .text(encodeJSON(rule.excludedDates)), .integer(rule.isReliable ? 1 : 0), .integer(rule.isActive ? 1 : 0), .text(rule.id)]
        )
    }

    private func validateStages(_ stages: [RecurringAmountStage]) throws {
        for stage in stages {
            if case .absolute(let cents) = stage.adjustment, cents <= 0 {
                throw FinanceDatabaseError.invalid("Eine Betragsstufe muss einen positiven Gesamtbetrag ergeben.")
            }
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "null"
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from text: String?, default defaultValue: T) -> T {
        guard let text, let data = text.data(using: .utf8), let decoded = try? JSONDecoder().decode(T.self, from: data) else { return defaultValue }
        return decoded
    }

    public func deleteRecurringRule(id: String) throws {
        try run("DELETE FROM recurring_rules WHERE id = ?", [.text(id)])
    }

    public func setRuleActive(id: String, active: Bool) throws {
        try run("UPDATE recurring_rules SET is_active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", [.integer(active ? 1 : 0), .text(id)])
    }

    public func upsertBudget(month: String, categoryID: String, plannedCents: Int) throws {
        try run(
            "INSERT INTO budgets (id, month, category_id, planned_cents) VALUES (?, ?, ?, ?) ON CONFLICT(month, category_id) DO UPDATE SET planned_cents = excluded.planned_cents, updated_at = CURRENT_TIMESTAMP",
            [.text(UUID().uuidString), .text(month), .text(categoryID), .integer(max(0, plannedCents))]
        )
    }

    public func addCategory(name: String, kind: EntryKind, iconName: String = "tag") throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FinanceDatabaseError.invalid("Der Kategoriename fehlt.") }
        try run("INSERT INTO categories (id, name, kind, icon_name) VALUES (?, ?, ?, ?)", [.text(UUID().uuidString), .text(trimmed), .text(kind.rawValue), .text(iconName)])
    }

    public func updateCategory(_ category: FinanceCategory) throws {
        let trimmed = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FinanceDatabaseError.invalid("Der Kategoriename fehlt.") }
        try run(
            "UPDATE categories SET name = ?, kind = ?, icon_name = ? WHERE id = ?",
            [.text(trimmed), .text(category.kind.rawValue), .text(category.iconName), .text(category.id)]
        )
    }

    public func deleteCategory(id: String) throws {
        try transaction {
            try run("UPDATE entries SET category_id = NULL, is_archived = 0 WHERE category_id = ?", [.text(id)])
            try run("UPDATE recurring_rules SET category_id = NULL WHERE category_id = ?", [.text(id)])
            try run("DELETE FROM budgets WHERE category_id = ?", [.text(id)])
            try run("DELETE FROM categories WHERE id = ?", [.text(id)])
        }
    }

    @discardableResult
    public func importBankEntries(_ imported: [BankImportEntry]) throws -> Int {
        guard !imported.isEmpty else { return 0 }
        let validAccounts = Set(try accounts().map(\.id))
        let validCategories = Set(try categories().map(\.id))
        var inserted = 0
        try transaction {
            for item in imported {
                guard item.amountCents > 0, validAccounts.contains(item.accountID) else { continue }
                if item.kind == .transfer {
                    guard let target = item.transferAccountID,
                          validAccounts.contains(target), target != item.accountID else { continue }
                }
                if let categoryID = item.categoryID, !validCategories.contains(categoryID) { continue }
                let duplicate: Bool
                if let fingerprint = item.fingerprint {
                    duplicate = try scalarInt("SELECT COUNT(*) FROM bank_import_records WHERE fingerprint = ?", [.text(fingerprint)]) > 0
                } else {
                    duplicate = try scalarInt(
                        "SELECT COUNT(*) FROM entries WHERE account_id = ? AND planned_date = ? AND amount_cents = ? AND kind = ? AND COALESCE(transfer_account_id, '') = COALESCE(?, '') AND note = 'CSV-Import'",
                        [.text(item.accountID), .text(item.date), .integer(item.amountCents), .text(item.kind.rawValue), .optionalText(item.transferAccountID)]
                    ) > 0
                }
                guard !duplicate else { continue }
                let entryID = UUID().uuidString
                try run(
                    "INSERT INTO entries (id,title,amount_cents,kind,account_id,transfer_account_id,category_id,planned_date,actual_date,status,note,is_reliable,affects_balance,is_archived) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,0)",
                    [.text(entryID), .text(item.title), .integer(item.amountCents), .text(item.kind.rawValue), .text(item.accountID), .optionalText(item.transferAccountID), .optionalText(item.categoryID), .text(item.date), .text(item.date), .text(EntryStatus.booked.rawValue), .text("CSV-Import"), .integer(0), .integer(0)]
                )
                if let fingerprint = item.fingerprint {
                    try run("INSERT INTO bank_import_records (fingerprint, entry_id) VALUES (?, ?)", [.text(fingerprint), .text(entryID)])
                }
                inserted += 1
            }
        }
        return inserted
    }

    public func exportData(to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(backup())
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    public func importData(from url: URL) throws -> URL {
        let data = try Data(contentsOf: url)
        let imported = try decodedBackup(from: data)
        try validate(imported)

        let recoveryDirectory = fileURL.deletingLastPathComponent().appending(path: "Sicherungen", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let recoveryURL = recoveryDirectory.appending(path: "vor-import-\(stamp).json")
        try exportData(to: recoveryURL)

        try transaction {
            try run("DELETE FROM entries")
            try run("DELETE FROM budgets")
            try run("DELETE FROM recurring_rules")
            try run("DELETE FROM categories")
            try run("DELETE FROM accounts")

            for account in imported.accounts {
                try run(
                    "INSERT INTO accounts (id,name,kind,balance_cents,balance_as_of,buffer_cents,color_hex,is_primary,needs_review) VALUES (?,?,?,?,?,?,?,?,?)",
                    [.text(account.id), .text(account.name), .text(account.kind.rawValue), .integer(account.currentBalanceCents), .text(account.balanceAsOf), .integer(account.minimumBufferCents), .text(account.colorHex), .integer(account.isPrimary ? 1 : 0), .integer(account.needsReview ? 1 : 0)]
                )
            }
            for category in imported.categories {
                try run(
                    "INSERT INTO categories (id,name,kind,icon_name) VALUES (?,?,?,?)",
                    [.text(category.id), .text(category.name), .text(category.kind.rawValue), .text(category.iconName)]
                )
            }
            for rule in imported.rules {
                try run(
                    "INSERT INTO recurring_rules (id,title,amount_cents,kind,account_id,transfer_account_id,category_id,frequency,interval_count,start_date,end_date,due_day,schedule_json,amount_stages_json,excluded_dates_json,is_reliable,is_active,needs_review) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    [.text(rule.id), .text(rule.title), .integer(rule.amountCents), .text(rule.kind.rawValue), .text(rule.accountID), .optionalText(rule.transferAccountID), .optionalText(rule.categoryID), .text(rule.frequency.rawValue), .integer(rule.interval), .text(rule.startDate), .optionalText(rule.endDate), .optionalInteger(rule.dueDay), .text(encodeJSON(rule.schedule)), .text(encodeJSON(rule.amountStages)), .text(encodeJSON(rule.excludedDates)), .integer(rule.isReliable ? 1 : 0), .integer(rule.isActive ? 1 : 0), .integer(rule.needsReview ? 1 : 0)]
                )
            }
            for entry in imported.entries {
                try run(
                    "INSERT INTO entries (id,title,amount_cents,kind,account_id,transfer_account_id,category_id,recurrence_id,planned_date,actual_date,status,note,is_reliable,affects_balance,is_archived) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    [.text(entry.id), .text(entry.title), .integer(entry.amountCents), .text(entry.kind.rawValue), .text(entry.accountID), .optionalText(entry.transferAccountID), .optionalText(entry.categoryID), .optionalText(entry.recurrenceID), .text(entry.plannedDate), .optionalText(entry.actualDate), .text(entry.status.rawValue), .optionalText(entry.note), .integer(entry.isReliable ? 1 : 0), .integer(entry.affectsBalance ? 1 : 0), .integer(entry.isArchived ? 1 : 0)]
                )
            }
            for budget in imported.budgets {
                try run(
                    "INSERT INTO budgets (id,month,category_id,planned_cents) VALUES (?,?,?,?)",
                    [.text(budget.id), .text(budget.month), .text(budget.categoryID), .integer(budget.plannedCents)]
                )
            }
            let restoredEntryIDs = Set(imported.entries.map(\.id))
            for record in imported.bankImportRecords ?? [] where restoredEntryIDs.contains(record.entryID) {
                try run("INSERT OR IGNORE INTO bank_import_records (fingerprint, entry_id) VALUES (?, ?)", [.text(record.fingerprint), .text(record.entryID)])
            }
            for attachment in imported.attachments ?? [] {
                try run(
                    "INSERT INTO entry_attachments (id,entry_id,file_name,stored_name,size_bytes,sha256,created_at) VALUES (?,?,?,?,?,?,?)",
                    [.text(attachment.id), .text(attachment.entryID), .text(attachment.fileName), .text(attachment.storedName), .integer(attachment.sizeBytes), .text(attachment.sha256), .text(attachment.createdAt.isEmpty ? "1970-01-01 00:00:00" : attachment.createdAt)]
                )
            }
        }
        return recoveryURL
    }

    /// Fingerprints of previously imported bank rows, used to flag repeats in
    /// the import preview before anything is written.
    public func bankImportFingerprints() throws -> Set<String> {
        Set(try query("SELECT fingerprint FROM bank_import_records") { statement in text(statement, 0) })
    }

    private func bankImportRecords() throws -> [BankImportRecord] {
        try query("SELECT fingerprint, entry_id FROM bank_import_records ORDER BY fingerprint") { statement in
            BankImportRecord(fingerprint: text(statement, 0), entryID: text(statement, 1))
        }
    }

    private func backup() throws -> FinanceBackup {
        FinanceBackup(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            accounts: try accounts(),
            categories: try categories(),
            entries: try entries(),
            rules: try recurringRules(),
            budgets: try storedBudgets(),
            bankImportRecords: try bankImportRecords(),
            attachments: try allAttachments()
        )
    }

    private func decodedBackup(from data: Data) throws -> FinanceBackup {
        let decoder = JSONDecoder()
        if let backup = try? decoder.decode(FinanceBackup.self, from: data) {
            guard backup.schemaVersion == 1 else {
                throw FinanceDatabaseError.invalid("Diese Sicherung verwendet eine nicht unterstützte Version.")
            }
            return backup
        }
        if let legacy = try? decoder.decode(FinanceSnapshot.self, from: data) {
            return FinanceBackup(
                exportedAt: "Unbekannt",
                accounts: legacy.accounts,
                categories: legacy.categories,
                entries: legacy.entries,
                rules: legacy.rules,
                budgets: legacy.budgets
            )
        }
        throw FinanceDatabaseError.invalid("Die Datei ist keine gültige Sicherung von Mein Finanzplan.")
    }

    private func validate(_ backup: FinanceBackup) throws {
        guard !backup.accounts.isEmpty else { throw FinanceDatabaseError.invalid("Die Sicherung enthält keine Konten.") }
        let accountIDs = Set(backup.accounts.map(\.id))
        let categoryIDs = Set(backup.categories.map(\.id))
        let ruleIDs = Set(backup.rules.map(\.id))
        guard accountIDs.count == backup.accounts.count,
              categoryIDs.count == backup.categories.count,
              ruleIDs.count == backup.rules.count,
              Set(backup.entries.map(\.id)).count == backup.entries.count else {
            throw FinanceDatabaseError.invalid("Die Sicherung enthält doppelte Kennungen.")
        }
        for entry in backup.entries {
            guard entry.amountCents > 0, accountIDs.contains(entry.accountID) else {
                throw FinanceDatabaseError.invalid("Eine Buchung verweist auf ungültige Daten.")
            }
            if let target = entry.transferAccountID, !accountIDs.contains(target) || target == entry.accountID {
                throw FinanceDatabaseError.invalid("Eine Umbuchung enthält ein ungültiges Zielkonto.")
            }
            if let category = entry.categoryID, !categoryIDs.contains(category) {
                throw FinanceDatabaseError.invalid("Eine Buchung verweist auf eine unbekannte Kategorie.")
            }
            if let rule = entry.recurrenceID, !ruleIDs.contains(rule) {
                throw FinanceDatabaseError.invalid("Eine Buchung verweist auf eine unbekannte Wiederholung.")
            }
        }
        for rule in backup.rules {
            guard rule.amountCents > 0, rule.interval > 0, accountIDs.contains(rule.accountID) else {
                throw FinanceDatabaseError.invalid("Eine Wiederholung verweist auf ungültige Daten.")
            }
            if let target = rule.transferAccountID, !accountIDs.contains(target) || target == rule.accountID {
                throw FinanceDatabaseError.invalid("Eine wiederkehrende Umbuchung enthält ein ungültiges Zielkonto.")
            }
            if let category = rule.categoryID, !categoryIDs.contains(category) {
                throw FinanceDatabaseError.invalid("Eine Wiederholung verweist auf eine unbekannte Kategorie.")
            }
        }
        guard backup.budgets.allSatisfy({ categoryIDs.contains($0.categoryID) && $0.plannedCents >= 0 }) else {
            throw FinanceDatabaseError.invalid("Ein Budget verweist auf eine ungültige Kategorie.")
        }
        let attachments = backup.attachments ?? []
        let entryIDs = Set(backup.entries.map(\.id))
        guard Set(attachments.map(\.id)).count == attachments.count,
              attachments.allSatisfy({
                  entryIDs.contains($0.entryID) && AttachmentStore.isValidStoredName($0.storedName)
                      && $0.sizeBytes >= 0 && !$0.fileName.isEmpty
              }) else {
            throw FinanceDatabaseError.invalid("Die Sicherung enthält ungültige Beleg-Angaben.")
        }
    }

    private static func defaultFileURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appending(path: "MeinFinanzplan", directoryHint: .isDirectory).appending(path: "finanzplan.sqlite")
    }

    private func createSchema() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL,
            balance_cents INTEGER NOT NULL, balance_as_of TEXT NOT NULL,
            buffer_cents INTEGER NOT NULL DEFAULT 0, color_hex TEXT NOT NULL,
            is_primary INTEGER NOT NULL DEFAULT 0, needs_review INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT;
        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,
            icon_name TEXT NOT NULL DEFAULT 'tag',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT;
        CREATE TABLE IF NOT EXISTS entries (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, amount_cents INTEGER NOT NULL,
            kind TEXT NOT NULL, account_id TEXT NOT NULL REFERENCES accounts(id),
            transfer_account_id TEXT REFERENCES accounts(id), category_id TEXT REFERENCES categories(id),
            recurrence_id TEXT REFERENCES recurring_rules(id),
            planned_date TEXT NOT NULL, actual_date TEXT, status TEXT NOT NULL,
            note TEXT, is_reliable INTEGER NOT NULL DEFAULT 0, affects_balance INTEGER NOT NULL DEFAULT 0,
            is_archived INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT;
        CREATE TABLE IF NOT EXISTS recurring_rules (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, amount_cents INTEGER NOT NULL,
            kind TEXT NOT NULL, account_id TEXT NOT NULL REFERENCES accounts(id),
            transfer_account_id TEXT REFERENCES accounts(id), category_id TEXT REFERENCES categories(id),
            frequency TEXT NOT NULL, interval_count INTEGER NOT NULL DEFAULT 1,
            start_date TEXT NOT NULL, end_date TEXT, due_day INTEGER,
            schedule_json TEXT, amount_stages_json TEXT NOT NULL DEFAULT '[]', excluded_dates_json TEXT NOT NULL DEFAULT '[]',
            is_reliable INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1,
            needs_review INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT;
        CREATE TABLE IF NOT EXISTS budgets (
            id TEXT PRIMARY KEY, month TEXT NOT NULL, category_id TEXT NOT NULL REFERENCES categories(id),
            planned_cents INTEGER NOT NULL, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(month, category_id)
        ) STRICT;
        CREATE TABLE IF NOT EXISTS bank_import_records (
            fingerprint TEXT PRIMARY KEY,
            entry_id TEXT NOT NULL UNIQUE REFERENCES entries(id) ON DELETE CASCADE,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT;
        CREATE TABLE IF NOT EXISTS entry_attachments (
            id TEXT PRIMARY KEY,
            entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
            file_name TEXT NOT NULL, stored_name TEXT NOT NULL,
            size_bytes INTEGER NOT NULL, sha256 TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT;
        CREATE INDEX IF NOT EXISTS idx_attachments_entry ON entry_attachments(entry_id);
        CREATE INDEX IF NOT EXISTS idx_attachments_stored ON entry_attachments(stored_name);
        CREATE INDEX IF NOT EXISTS idx_entries_date ON entries(planned_date);
        CREATE INDEX IF NOT EXISTS idx_rules_active ON recurring_rules(is_active, start_date);
        """)
    }

    private func migrateSchema() throws {
        if try !columnExists("icon_name", in: "categories") {
            try execute("ALTER TABLE categories ADD COLUMN icon_name TEXT NOT NULL DEFAULT 'tag'")
        }
        if try !columnExists("is_archived", in: "entries") {
            try execute("ALTER TABLE entries ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0")
        }
        if try !columnExists("schedule_json", in: "recurring_rules") {
            try execute("ALTER TABLE recurring_rules ADD COLUMN schedule_json TEXT")
            try execute("""
            UPDATE recurring_rules SET schedule_json =
                CASE WHEN due_day IS NULL THEN '{"type":"fixedDay"}' ELSE '{"type":"fixedDay","day":' || due_day || '}' END
            WHERE schedule_json IS NULL;
            """)
        }
        if try !columnExists("amount_stages_json", in: "recurring_rules") {
            try execute("ALTER TABLE recurring_rules ADD COLUMN amount_stages_json TEXT NOT NULL DEFAULT '[]'")
        }
        if try !columnExists("excluded_dates_json", in: "recurring_rules") {
            try execute("ALTER TABLE recurring_rules ADD COLUMN excluded_dates_json TEXT NOT NULL DEFAULT '[]'")
        }
        let iconByCategoryID = [
            "cat-salary": "banknote", "cat-pension": "building.columns", "cat-child": "figure.2.and.child.holdinghands",
            "cat-other-income": "plus.circle", "cat-rent": "house", "cat-insurance": "shield",
            "cat-phone": "iphone", "cat-tickets": "tram", "cat-food": "cart",
            "cat-clothing": "tshirt", "cat-leisure": "sparkles", "cat-orders": "shippingbox",
            "cat-subscriptions": "repeat", "cat-broadcast": "tv", "cat-savings": "banknote.fill"
        ]
        for (id, icon) in iconByCategoryID {
            try run("UPDATE categories SET icon_name = ? WHERE id = ? AND icon_name = 'tag'", [.text(icon), .text(id)])
        }
    }

    private func columnExists(_ column: String, in table: String) throws -> Bool {
        try query("PRAGMA table_info(\(table))") { statement in text(statement, 1) }.contains(column)
    }

    private func seedIfNeeded() throws {
        guard try scalarInt("SELECT COUNT(*) FROM accounts") == 0 else { return }
        let today = FinanceCalendar.today()
        try transaction {
            try execute("""
            INSERT INTO accounts VALUES
              ('acc-giro','Girokonto','CHECKING',0,'\(today)',10000,'#2B8A73',1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('acc-sparen','Tagesgeld','SAVINGS',290000,'\(today)',50000,'#4C82B8',0,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('acc-cash','Bargeld','CASH',0,'\(today)',0,'#A47742',0,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP);
            INSERT INTO categories (id,name,kind,icon_name) VALUES
              ('cat-salary','Gehalt Netto','INCOME','banknote'),('cat-pension','Waisenrente Netto','INCOME','building.columns'),
              ('cat-child','Kindergeld Netto','INCOME','figure.2.and.child.holdinghands'),('cat-other-income','Sonstige Einnahmen','INCOME','plus.circle'),
              ('cat-rent','Miete','EXPENSE','house'),('cat-insurance','Versicherungen','EXPENSE','shield'),
              ('cat-phone','Telefon','EXPENSE','iphone'),('cat-tickets','Fahrkarten','EXPENSE','tram'),
              ('cat-food','Lebensmittel','EXPENSE','cart'),('cat-clothing','Kleidung','EXPENSE','tshirt'),
              ('cat-leisure','Freizeit','EXPENSE','sparkles'),('cat-orders','Bestellungen','EXPENSE','shippingbox'),
              ('cat-subscriptions','Abos','EXPENSE','repeat'),('cat-broadcast','Rundfunkbeitrag','EXPENSE','tv'),
              ('cat-savings','Sparen','TRANSFER','banknote.fill');
            INSERT INTO recurring_rules (id,title,amount_cents,kind,account_id,transfer_account_id,category_id,frequency,interval_count,start_date,end_date,due_day,schedule_json,is_reliable,is_active,needs_review,created_at,updated_at) VALUES
              ('rec-salary','Gehalt',108151,'INCOME','acc-giro',NULL,'cat-salary','MONTHLY',1,'2026-09-25','2027-08-25',25,'{"type":"fixedDay","day":25}',1,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('rec-pension','Waisenrente',36600,'INCOME','acc-giro',NULL,'cat-pension','MONTHLY',1,'2026-10-01',NULL,1,'{"type":"fixedDay","day":1}',1,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('rec-child','Kindergeld',25900,'INCOME','acc-giro',NULL,'cat-child','MONTHLY',1,'2026-10-08',NULL,8,'{"type":"fixedDay","day":8}',1,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('rec-rent-high','Miete',82000,'EXPENSE','acc-giro',NULL,'cat-rent','MONTHLY',1,'2026-11-03','2027-02-03',3,'{"type":"fixedDay","day":3}',0,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('rec-rent','Miete',57000,'EXPENSE','acc-giro',NULL,'cat-rent','MONTHLY',1,'2027-03-03',NULL,3,'{"type":"fixedDay","day":3}',0,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('rec-insurance','Versicherungen',4800,'EXPENSE','acc-giro',NULL,'cat-insurance','MONTHLY',1,'2026-09-15',NULL,15,'{"type":"fixedDay","day":15}',0,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('rec-phone','Telefon',1000,'EXPENSE','acc-giro',NULL,'cat-phone','MONTHLY',1,'2026-10-12',NULL,12,'{"type":"fixedDay","day":12}',0,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('rec-tickets','Fahrkarten',11000,'EXPENSE','acc-giro',NULL,'cat-tickets','MONTHLY',1,'2026-10-01',NULL,1,'{"type":"fixedDay","day":1}',0,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP),
              ('rec-subscriptions','Abos',2000,'EXPENSE','acc-giro',NULL,'cat-subscriptions','MONTHLY',1,'2026-09-10',NULL,10,'{"type":"fixedDay","day":10}',0,1,1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP);
            INSERT INTO entries (id,title,amount_cents,kind,account_id,transfer_account_id,category_id,planned_date,status,note,is_reliable,affects_balance) VALUES
              ('tx-savings-oct','Sparrate Oktober',100000,'TRANSFER','acc-giro','acc-sparen','cat-savings','2026-10-02','PLANNED','Aus Excel übernommen',0,0),
              ('tx-savings-nov','Sparrate November',30000,'TRANSFER','acc-giro','acc-sparen','cat-savings','2026-11-02','PLANNED','Aus Excel übernommen',0,0),
              ('tx-savings-dec','Sparrate Dezember',35000,'TRANSFER','acc-giro','acc-sparen','cat-savings','2026-12-02','PLANNED','Aus Excel übernommen',0,0),
              ('tx-other-income-dec','Sonstige Einnahme',20000,'INCOME','acc-giro',NULL,'cat-other-income','2026-12-15','PLANNED','Aus Excel übernommen',0,0);
            INSERT INTO budgets (id,month,category_id,planned_cents) VALUES
              ('budget-food','2026-09','cat-food',25000),('budget-tickets','2026-09','cat-tickets',11000),
              ('budget-leisure','2026-09','cat-leisure',2000),('budget-orders','2026-09','cat-orders',1000);
            """)
        }
    }

    private func accounts() throws -> [Account] {
        try query("SELECT id,name,kind,balance_cents,balance_as_of,buffer_cents,color_hex,is_primary,needs_review FROM accounts ORDER BY is_primary DESC,name") { statement in
            Account(id: text(statement, 0), name: text(statement, 1), kind: AccountKind(rawValue: text(statement, 2)) ?? .other, currentBalanceCents: integer(statement, 3), balanceAsOf: text(statement, 4), minimumBufferCents: integer(statement, 5), colorHex: text(statement, 6), isPrimary: integer(statement, 7) == 1, needsReview: integer(statement, 8) == 1)
        }
    }

    private func categories() throws -> [FinanceCategory] {
        try query("SELECT id,name,kind,icon_name FROM categories ORDER BY name") { statement in
            FinanceCategory(id: text(statement, 0), name: text(statement, 1), kind: EntryKind(rawValue: text(statement, 2)) ?? .expense, iconName: text(statement, 3))
        }
    }

    private func entries() throws -> [FinanceEntry] {
        try query("SELECT id,title,amount_cents,kind,account_id,transfer_account_id,category_id,recurrence_id,planned_date,actual_date,status,note,is_reliable,affects_balance,is_archived FROM entries ORDER BY planned_date DESC,created_at DESC") { statement in
            FinanceEntry(id: text(statement, 0), title: text(statement, 1), amountCents: integer(statement, 2), kind: EntryKind(rawValue: text(statement, 3)) ?? .expense, accountID: text(statement, 4), transferAccountID: optionalText(statement, 5), categoryID: optionalText(statement, 6), recurrenceID: optionalText(statement, 7), plannedDate: text(statement, 8), actualDate: optionalText(statement, 9), status: EntryStatus(rawValue: text(statement, 10)) ?? .planned, note: optionalText(statement, 11), isReliable: integer(statement, 12) == 1, affectsBalance: integer(statement, 13) == 1, isArchived: integer(statement, 14) == 1)
        }
    }

    private func entry(id: String) throws -> FinanceEntry? {
        try query(
            "SELECT id,title,amount_cents,kind,account_id,transfer_account_id,category_id,recurrence_id,planned_date,actual_date,status,note,is_reliable,affects_balance,is_archived FROM entries WHERE id = ? LIMIT 1",
            [.text(id)]
        ) { statement in
            FinanceEntry(id: text(statement, 0), title: text(statement, 1), amountCents: integer(statement, 2), kind: EntryKind(rawValue: text(statement, 3)) ?? .expense, accountID: text(statement, 4), transferAccountID: optionalText(statement, 5), categoryID: optionalText(statement, 6), recurrenceID: optionalText(statement, 7), plannedDate: text(statement, 8), actualDate: optionalText(statement, 9), status: EntryStatus(rawValue: text(statement, 10)) ?? .planned, note: optionalText(statement, 11), isReliable: integer(statement, 12) == 1, affectsBalance: integer(statement, 13) == 1, isArchived: integer(statement, 14) == 1)
        }.first
    }

    private func archiveOldManualEntries(today: String) throws {
        let monthStart = String(today.prefix(7)) + "-01"
        try run(
            "UPDATE entries SET is_archived = 1 WHERE recurrence_id IS NULL AND category_id IS NOT NULL AND planned_date < ? AND is_archived = 0",
            [.text(monthStart)]
        )
    }

    private func recurringRules() throws -> [RecurringRule] {
        try query("SELECT id,title,amount_cents,kind,account_id,transfer_account_id,category_id,frequency,interval_count,start_date,end_date,due_day,schedule_json,amount_stages_json,excluded_dates_json,is_reliable,is_active,needs_review FROM recurring_rules ORDER BY is_active DESC,start_date,title") { statement in
            let dueDay = optionalInteger(statement, 11)
            let schedule = decodeJSON(RecurrenceSchedule.self, from: optionalText(statement, 12), default: .fixedDay(dueDay))
            let amountStages = decodeJSON([RecurringAmountStage].self, from: optionalText(statement, 13), default: [])
            let excludedDates = decodeJSON([String].self, from: optionalText(statement, 14), default: [])
            return RecurringRule(id: text(statement, 0), title: text(statement, 1), amountCents: integer(statement, 2), kind: EntryKind(rawValue: text(statement, 3)) ?? .expense, accountID: text(statement, 4), transferAccountID: optionalText(statement, 5), categoryID: optionalText(statement, 6), frequency: RecurrenceFrequency(rawValue: text(statement, 7)) ?? .monthly, interval: integer(statement, 8), startDate: text(statement, 9), endDate: optionalText(statement, 10), schedule: schedule, amountStages: amountStages, excludedDates: excludedDates, isReliable: integer(statement, 15) == 1, isActive: integer(statement, 16) == 1, needsReview: integer(statement, 17) == 1)
        }
    }

    private func budgets(month: String, entries: [FinanceEntry]) throws -> [Budget] {
        let actualByCategory = Dictionary(grouping: entries.filter { $0.status == .booked && ($0.actualDate ?? $0.plannedDate).hasPrefix(month) }, by: { $0.categoryID ?? "" }).mapValues { $0.reduce(0) { $0 + $1.amountCents } }
        return try query("SELECT id,month,category_id,planned_cents FROM budgets WHERE month = ? ORDER BY category_id", [.text(month)]) { statement in
            let categoryID = text(statement, 2)
            return Budget(id: text(statement, 0), month: text(statement, 1), categoryID: categoryID, plannedCents: integer(statement, 3), actualCents: actualByCategory[categoryID, default: 0])
        }
    }

    private func storedBudgets() throws -> [Budget] {
        try query("SELECT id,month,category_id,planned_cents FROM budgets ORDER BY month,category_id") { statement in
            Budget(id: text(statement, 0), month: text(statement, 1), categoryID: text(statement, 2), plannedCents: integer(statement, 3))
        }
    }

    private func applyBalanceEffect(for entry: FinanceEntry, direction: Int) throws {
        let signed: Int
        switch entry.kind {
        case .income: signed = entry.amountCents
        case .expense, .transfer: signed = -entry.amountCents
        }
        try run("UPDATE accounts SET balance_cents = balance_cents + ?, balance_as_of = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", [.integer(signed * direction), .text(entry.actualDate ?? entry.plannedDate), .text(entry.accountID)])
        if entry.kind == .transfer, let target = entry.transferAccountID {
            try run("UPDATE accounts SET balance_cents = balance_cents + ?, balance_as_of = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", [.integer(entry.amountCents * direction), .text(entry.actualDate ?? entry.plannedDate), .text(target)])
        }
    }

    private enum SQLiteValue {
        case text(String)
        case optionalText(String?)
        case integer(Int)
        case optionalInteger(Int?)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection))
            sqlite3_free(error)
            throw FinanceDatabaseError.statement(message)
        }
    }

    private func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        try withStatement(sql, values) { statement in
            guard sqlite3_step(statement) == SQLITE_DONE else { throw FinanceDatabaseError.statement(String(cString: sqlite3_errmsg(connection))) }
        }
    }

    private func scalarInt(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int {
        try withStatement(sql, values) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { throw FinanceDatabaseError.statement(String(cString: sqlite3_errmsg(connection))) }
            return integer(statement, 0)
        }
    }

    private func query<T>(_ sql: String, _ values: [SQLiteValue] = [], transform: (OpaquePointer) -> T) throws -> [T] {
        try withStatement(sql, values) { statement in
            var result: [T] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW: result.append(transform(statement))
                case SQLITE_DONE: return result
                default: throw FinanceDatabaseError.statement(String(cString: sqlite3_errmsg(connection)))
                }
            }
        }
    }

    private func withStatement<T>(_ sql: String, _ values: [SQLiteValue], body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FinanceDatabaseError.statement(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() { try bind(value, to: statement, at: Int32(offset + 1)) }
        return try body(statement)
    }

    private func bind(_ value: SQLiteValue, to statement: OpaquePointer, at index: Int32) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = switch value {
        case .text(let value): sqlite3_bind_text(statement, index, value, -1, transient)
        case .optionalText(let value):
            if let value { sqlite3_bind_text(statement, index, value, -1, transient) } else { sqlite3_bind_null(statement, index) }
        case .integer(let value): sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case .optionalInteger(let value):
            if let value { sqlite3_bind_int64(statement, index, sqlite3_int64(value)) } else { sqlite3_bind_null(statement, index) }
        }
        guard result == SQLITE_OK else {
            throw FinanceDatabaseError.statement(String(cString: sqlite3_errmsg(connection)))
        }
    }

    private func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try work()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private func optionalText(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : text(statement, column)
    }

    private func integer(_ statement: OpaquePointer, _ column: Int32) -> Int {
        Int(sqlite3_column_int64(statement, column))
    }

    private func optionalInteger(_ statement: OpaquePointer, _ column: Int32) -> Int? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : integer(statement, column)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
