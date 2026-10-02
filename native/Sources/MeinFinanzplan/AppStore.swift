import Foundation
import FinanceCore
import Observation

private struct PeriodRangeKey: Hashable {
    let start: String
    let end: String
}

@MainActor
@Observable
final class AppStore {
    private(set) var snapshot: FinanceSnapshot = .empty
    private(set) var revision = 0
    private(set) var attachmentCounts: [String: Int] = [:]
    var errorMessage: String?
    var databaseFileURL: URL?
    let calendarSync: AppleCalendarSyncManager

    private let database: FinanceDatabase?
    private var accountsByID: [String: Account] = [:]
    private var categoriesByID: [String: FinanceCategory] = [:]
    @ObservationIgnored private var timelineCache: [PeriodRangeKey: [ForecastPoint]] = [:]
    @ObservationIgnored private var occurrenceCache: [PeriodRangeKey: [FinanceEntry]] = [:]

    init() {
        let resolvedDatabase: FinanceDatabase?
        var startupError: String?
        do {
            resolvedDatabase = try FinanceDatabase()
        } catch {
            resolvedDatabase = nil
            startupError = "Die Datenbank konnte nicht geöffnet werden. Deine Datei wurde nicht verändert. \(error.localizedDescription)"
        }
        database = resolvedDatabase
        databaseFileURL = resolvedDatabase?.fileURL
        let expectedURL = resolvedDatabase?.fileURL ?? Self.expectedDatabaseURL
        calendarSync = AppleCalendarSyncManager(databaseFileURL: expectedURL)
        if resolvedDatabase != nil { reload() }
        if let startupError { errorMessage = startupError }
    }

    func reload() {
        guard let database else {
            errorMessage = "Die Datenbank ist nicht verfügbar. Starte die App neu oder stelle eine Sicherung wieder her."
            return
        }
        do {
            let refreshed = try database.snapshot(days: 365)
            snapshot = refreshed
            attachmentCounts = (try? database.attachmentCounts()) ?? [:]
            accountsByID = Dictionary(uniqueKeysWithValues: refreshed.accounts.map { ($0.id, $0) })
            categoriesByID = Dictionary(uniqueKeysWithValues: refreshed.categories.map { ($0.id, $0) })
            timelineCache.removeAll(keepingCapacity: true)
            occurrenceCache.removeAll(keepingCapacity: true)
            revision &+= 1
            triggerAppleCalendarSync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The snapshot's "today" is fixed at load time; long-running sessions
    /// (menu bar item) call this after midnight or wake-up.
    func reloadIfDayChanged() {
        guard database != nil, snapshot.today != FinanceCalendar.today() else { return }
        reload()
    }

    /// Mirrors booked entries and generated recurrences within the configured
    /// horizon (see `AppleCalendarSyncManager`) into the managed Apple
    /// Calendar. No-op unless the user opted in and access was granted.
    func triggerAppleCalendarSync() {
        guard calendarSync.isEnabled else { return }
        let start = FinanceCalendar.addingDays(-AppleCalendarSyncManager.horizonDaysBackward, to: snapshot.today)
        let end = FinanceCalendar.addingDays(AppleCalendarSyncManager.horizonDaysForward, to: snapshot.today)
        let entries = occurrencesAndEntries(from: start, through: end)
        calendarSync.requestSync(entries: entries, accounts: snapshot.accounts, categories: snapshot.categories)
    }

    /// Re-establishes Calendar access after launch or returning from System
    /// Settings, then catches the mirror up with the current finance state.
    func resumeAppleCalendarSync() async {
        await calendarSync.resumeIfEnabled()
        triggerAppleCalendarSync()
    }

    private func perform(_ work: (FinanceDatabase) throws -> Void) {
        guard let database else {
            errorMessage = "Die Datenbank ist nicht verfügbar; es wurden keine Daten verändert."
            return
        }
        do {
            try work(database)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addAccount(name: String, kind: AccountKind, balanceCents: Int, bufferCents: Int, colorHex: String, isPrimary: Bool) {
        perform { try $0.addAccount(name: name, kind: kind, balanceCents: balanceCents, bufferCents: bufferCents, colorHex: colorHex, isPrimary: isPrimary) }
    }

    func updateAccount(_ account: Account) {
        perform { try $0.updateAccount(account) }
    }

    func confirmAccountBalance(id: String) {
        perform { try $0.confirmAccountBalance(id: id, date: snapshot.today) }
    }

    func deleteAccount(id: String) {
        perform { try $0.deleteAccount(id: id) }
    }

    func addEntry(_ entry: FinanceEntry) {
        perform { try $0.addEntry(entry) }
    }

    func updateEntry(_ entry: FinanceEntry) {
        perform { try $0.updateEntry(entry) }
    }

    func deleteEntry(id: String) {
        perform { try $0.deleteEntry(id: id) }
    }

    /// Saves a booking together with its receipt changes. Removals run before
    /// additions; an addition that fails is reported after the booking itself
    /// was stored.
    func saveEntry(_ entry: FinanceEntry, isNew: Bool, newAttachments: [URL], removedAttachmentIDs: [String]) {
        guard let database else {
            errorMessage = "Die Datenbank ist nicht verfügbar; es wurden keine Daten verändert."
            return
        }
        do {
            if isNew { try database.addEntry(entry) } else { try database.updateEntry(entry) }
            for id in removedAttachmentIDs { try database.removeAttachment(id: id) }
            if !newAttachments.isEmpty { try database.addAttachments(entryID: entry.id, sources: newAttachments) }
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }

    func attachments(for entryID: String) -> [EntryAttachment] {
        (try? database?.attachments(entryID: entryID)) ?? []
    }

    func attachmentURL(_ attachment: EntryAttachment) -> URL? {
        guard let url = database?.attachmentStore.fileURL(storedName: attachment.storedName),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var attachmentFolderURL: URL? { database?.attachmentStore.directory }

    var attachmentTotalBytes: Int { database?.attachmentStore.totalSize() ?? 0 }

    func missingAttachmentFileCount() -> Int {
        (try? database?.missingAttachmentFileCount()) ?? 0
    }

    func addRecurringRule(_ rule: RecurringRule) {
        perform { try $0.addRecurringRule(rule) }
    }

    func updateRecurringRule(_ rule: RecurringRule) {
        perform { try $0.updateRecurringRule(rule) }
    }

    func deleteRecurringRule(id: String) {
        perform { try $0.deleteRecurringRule(id: id) }
    }

    func setRuleActive(id: String, active: Bool) {
        perform { try $0.setRuleActive(id: id, active: active) }
    }

    func upsertBudget(month: String, categoryID: String, plannedCents: Int) {
        perform { try $0.upsertBudget(month: month, categoryID: categoryID, plannedCents: plannedCents) }
    }

    func addCategory(name: String, kind: EntryKind, iconName: String) {
        perform { try $0.addCategory(name: name, kind: kind, iconName: iconName) }
    }

    func updateCategory(_ category: FinanceCategory) {
        perform { try $0.updateCategory(category) }
    }

    func deleteCategory(id: String) {
        perform { try $0.deleteCategory(id: id) }
    }

    @discardableResult
    func importBankEntries(_ entries: [BankImportEntry]) -> Int? {
        guard let database else { errorMessage = "Die Datenbank ist nicht verfügbar."; return nil }
        do {
            let count = try database.importBankEntries(entries)
            reload()
            return count
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func bankImportFingerprints() -> Set<String> {
        (try? database?.bankImportFingerprints()) ?? []
    }

    func exportData(to url: URL) {
        guard let database else { errorMessage = "Die Datenbank ist nicht verfügbar."; return }
        do {
            try database.exportData(to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func importData(from url: URL) -> URL? {
        guard let database else { errorMessage = "Die Datenbank ist nicht verfügbar."; return nil }
        do {
            let recoveryURL = try database.importData(from: url)
            reload()
            return recoveryURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Account balances across an arbitrary calendar range, including history
    /// before today. Read-only and independent from the cached snapshot so the
    /// dashboard can navigate calendar periods without a full reload.
    func timeline(from start: String, through end: String) -> [ForecastPoint] {
        let key = PeriodRangeKey(start: start, end: end)
        if let cached = timelineCache[key] { return cached }
        let result = FinanceEngine.timeline(
            accounts: snapshot.accounts,
            entries: snapshot.entries,
            rules: snapshot.rules,
            today: snapshot.today,
            start: start,
            end: end
        )
        insert(result, for: key, into: &timelineCache)
        return result
    }

    /// Materialized entries plus generated future occurrences within an
    /// arbitrary calendar range, chronologically sorted.
    func occurrencesAndEntries(from start: String, through end: String) -> [FinanceEntry] {
        let key = PeriodRangeKey(start: start, end: end)
        if let cached = occurrenceCache[key] { return cached }
        let result = FinanceEngine.occurrencesAndEntries(
            entries: snapshot.entries,
            rules: snapshot.rules,
            today: snapshot.today,
            start: start,
            end: end
        )
        insert(result, for: key, into: &occurrenceCache)
        return result
    }

    private func insert<Value>(_ value: Value, for key: PeriodRangeKey, into cache: inout [PeriodRangeKey: Value]) {
        if cache.count >= 12, let oldestKey = cache.keys.first {
            cache.removeValue(forKey: oldestKey)
        }
        cache[key] = value
    }

    func account(_ id: String) -> Account? {
        accountsByID[id]
    }

    func category(_ id: String?) -> FinanceCategory? {
        guard let id else { return nil }
        return categoriesByID[id]
    }

    private static var expectedDatabaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base.appending(path: "MeinFinanzplan", directoryHint: .isDirectory).appending(path: "finanzplan.sqlite")
    }
}
