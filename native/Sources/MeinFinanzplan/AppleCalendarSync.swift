import AppKit
import EventKit
import FinanceCore
import Foundation

/// Live, one-way mirror of finance entries into a dedicated "Mein Finanzplan"
/// calendar via EventKit. Opt-in: nothing touches Calendar until the user
/// enables sync in Settings and grants access. No external dependency.
///
/// The sync is one-directional (app → Calendar) and self-contained: only
/// events this manager created are ever updated or removed, tracked by a
/// small entry-ID → event-identifier map persisted next to the finance
/// database so the mapping survives app relaunches.
@MainActor
@Observable
final class AppleCalendarSyncManager {

    /// Simplified view of `EKAuthorizationStatus` for UI purposes.
    enum PermissionState: Equatable {
        case notDetermined
        case authorized
        /// macOS granted write-only access (no read/update/delete of existing
        /// events). Insufficient for this sync, which must read and remove
        /// its own previously-created events. An upgrade to full access can
        /// be requested via `requestAccessUpgrade()`.
        case writeOnly
        case denied
        case restricted
    }

    static let calendarTitle = "Mein Finanzplan"
    /// How far past today booked entries stay mirrored, so recently settled
    /// items remain visible for a short while after the fact.
    static let horizonDaysBackward = 14
    /// How far into the future generated recurrences are mirrored. Keeps the
    /// calendar useful without flooding it with years of speculative entries.
    static let horizonDaysForward = 180

    private(set) var isEnabled: Bool
    private(set) var permissionState: PermissionState
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?
    private(set) var managedEventCount = 0
    private(set) var isSyncing = false
    private(set) var isRequestingAccess = false
    /// Human-readable calendar source (e.g. "iCloud", "Lokal", "Exchange"),
    /// so Settings can honestly disclose whether mirrored events may
    /// propagate to other devices via the user's Apple Calendar account.
    private(set) var calendarSourceDescription: String?

    /// Number of processed entries between cooperative yields inside the
    /// sync loop, so a large horizon never blocks scrolling/typing on the
    /// main actor for long.
    private static let yieldBatchSize = 25

    private let eventStore = EKEventStore()
    private let mappingFileURL: URL
    private var calendarIdentifier: String?
    private var syncedEvents: [String: SyncedEvent]
    private var pendingInput: SyncInput?
    private var shouldRemoveAllEvents = false

    private struct SyncedEvent: Codable {
        var eventIdentifier: String
        var signature: String
    }

    private struct SyncInput {
        var entries: [FinanceEntry]
        var accounts: [Account]
        var categories: [FinanceCategory]
    }

    private enum StoredKeys {
        static let enabled = "appleCalendarSyncEnabled"
        static let calendarIdentifier = "appleCalendarSyncCalendarIdentifier"
    }

    private enum SyncError: LocalizedError {
        case noCalendarSource
        case missingEventIdentifier

        var errorDescription: String? {
            switch self {
            case .noCalendarSource: "Es wurde keine Kalenderquelle für einen neuen Kalender gefunden."
            case .missingEventIdentifier: "Ein Kalendertermin wurde gespeichert, konnte danach aber nicht wiedergefunden werden."
            }
        }
    }

    init(databaseFileURL: URL?) {
        isEnabled = UserDefaults.standard.bool(forKey: StoredKeys.enabled)
        calendarIdentifier = UserDefaults.standard.string(forKey: StoredKeys.calendarIdentifier)
        let directory = databaseFileURL?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        mappingFileURL = directory.appendingPathComponent("apple-calendar-sync-map.json")
        let storedEvents = Self.loadMapping(from: mappingFileURL)
        syncedEvents = storedEvents
        managedEventCount = storedEvents.count
        permissionState = Self.permissionState(from: EKEventStore.authorizationStatus(for: .event))
    }

    // MARK: - Opt-in / opt-out

    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else {
            if enabled, permissionState != .authorized {
                _ = await requestAccess()
            }
            return
        }

        // Persist the person's intent even when macOS has denied access. This
        // lets the app resume automatically after access is granted in System
        // Settings instead of silently switching the toggle back off.
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: StoredKeys.enabled)

        if enabled {
            _ = await requestAccess()
        } else {
            pendingInput = nil
            if permissionState == .authorized {
                shouldRemoveAllEvents = true
                startQueueIfNeeded()
            }
            lastError = nil
        }
    }

    /// Re-requests calendar access. Used both for the initial opt-in prompt
    /// and, when macOS only granted write-only access, to offer the user a
    /// way to upgrade to full access without leaving the app.
    func requestAccessUpgrade() async {
        _ = await requestAccess()
    }

    /// Restores an existing opt-in after an app update. Ad-hoc signed builds
    /// can appear as a new code identity to macOS, so Calendar may require a
    /// fresh prompt even though the person's in-app preference is still on.
    func resumeIfEnabled() async {
        refreshPermissionState()
        guard isEnabled, permissionState != .authorized else { return }
        _ = await requestAccess()
    }

    @discardableResult
    private func requestAccess() async -> Bool {
        refreshPermissionState()
        if permissionState == .authorized {
            lastError = nil
            return true
        }
        guard !isRequestingAccess else { return false }
        guard permissionState == .notDetermined || permissionState == .writeOnly else {
            lastError = "Kein Kalenderzugriff. Bitte in den Systemeinstellungen unter Datenschutz & Sicherheit → Kalender erlauben."
            return false
        }

        isRequestingAccess = true
        defer { isRequestingAccess = false }
        do {
            // Calling this again when the system previously granted only
            // write-only access re-prompts for a full-access upgrade; when
            // status is notDetermined it shows the initial system prompt.
            _ = try await eventStore.requestFullAccessToEvents()
            refreshPermissionState()
            switch permissionState {
            case .authorized:
                lastError = nil
            case .writeOnly:
                lastError = "Es wurde nur Schreibzugriff erteilt. Zum Lesen und Entfernen eigener Ereignisse wird Vollzugriff benötigt."
            default:
                lastError = "Kalenderzugriff wurde nicht erteilt."
            }
            return permissionState == .authorized
        } catch {
            refreshPermissionState()
            lastError = error.localizedDescription
            return false
        }
    }

    /// Re-reads the system authorization status. Call when the app regains
    /// focus, since the user may have changed calendar access while away in
    /// System Settings.
    func refreshPermissionState() {
        let previous = permissionState
        let refreshed = Self.permissionState(from: EKEventStore.authorizationStatus(for: .event))
        permissionState = refreshed
        if refreshed == .authorized, previous != .authorized {
            // Apple documents that an event store may need resetting after
            // access changes so newly available calendars can be fetched.
            eventStore.reset()
            lastError = nil
        }
    }

    static func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Sync entry point

    /// Queues a sync for the given horizon-limited entries. Coalesces with any
    /// sync already running so overlapping reloads never race each other.
    func requestSync(entries: [FinanceEntry], accounts: [Account], categories: [FinanceCategory]) {
        guard isEnabled, permissionState == .authorized else { return }
        pendingInput = SyncInput(entries: entries, accounts: accounts, categories: categories)
        startQueueIfNeeded()
    }

    /// Marks the queue busy synchronously on the main actor before creating a
    /// task. This closes the scheduling window in which two callers could
    /// otherwise start overlapping EventKit commits.
    private func startQueueIfNeeded() {
        guard !isSyncing else { return }
        isSyncing = true
        Task { await drainQueue() }
    }

    private func drainQueue() async {
        while true {
            if shouldRemoveAllEvents {
                shouldRemoveAllEvents = false
                pendingInput = nil
                await removeAllManagedEvents()
                if !isEnabled { break }
            }

            guard isEnabled, permissionState == .authorized, let pending = pendingInput else { break }
            pendingInput = nil
            await performSync(pending)
        }
        isSyncing = false
    }

    private func performSync(_ input: SyncInput) async {
        do {
            let calendar = try ensureManagedCalendar()
            var updated = syncedEvents
            var seenEntryIDs = Set<String>()
            var didChange = false
            var pendingIdentifiers: [(entryID: String, event: EKEvent, signature: String)] = []

            if syncedEvents.isEmpty || syncedEvents.values.contains(where: { eventStore.event(withIdentifier: $0.eventIdentifier) == nil }) {
                for (entryID, event) in recoverManagedEvents(in: calendar) {
                    if updated[entryID].flatMap({ eventStore.event(withIdentifier: $0.eventIdentifier) }) == nil,
                       let identifier = event.eventIdentifier {
                        updated[entryID] = SyncedEvent(eventIdentifier: identifier, signature: "")
                    }
                }
            }

            var processedCount = 0
            for entry in input.entries where entry.status != .cancelled {
                seenEntryIDs.insert(entry.id)
                let signature = signature(for: entry, accounts: input.accounts, categories: input.categories)
                if let existing = updated[entry.id], existing.signature == signature,
                   eventStore.event(withIdentifier: existing.eventIdentifier) != nil {
                    continue
                }
                let event = updated[entry.id].flatMap { eventStore.event(withIdentifier: $0.eventIdentifier) }
                    ?? EKEvent(eventStore: eventStore)
                apply(entry: entry, accounts: input.accounts, categories: input.categories, to: event, calendar: calendar)
                try eventStore.save(event, span: .thisEvent, commit: false)
                didChange = true
                pendingIdentifiers.append((entry.id, event, signature))

                processedCount += 1
                if processedCount % Self.yieldBatchSize == 0 {
                    await Task.yield()
                }
            }

            // Work on a snapshot: mutating a dictionary while iterating its
            // live storage is undefined and can crash during a larger cleanup.
            let staleMappings = updated.filter { !seenEntryIDs.contains($0.key) }
            for (entryID, synced) in staleMappings {
                if let event = eventStore.event(withIdentifier: synced.eventIdentifier) {
                    try eventStore.remove(event, span: .thisEvent, commit: false)
                    didChange = true
                }
                updated.removeValue(forKey: entryID)

                processedCount += 1
                if processedCount % Self.yieldBatchSize == 0 {
                    await Task.yield()
                }
            }

            if didChange {
                try eventStore.commit()
            }
            for pending in pendingIdentifiers {
                guard let identifier = pending.event.eventIdentifier else {
                    throw SyncError.missingEventIdentifier
                }
                updated[pending.entryID] = SyncedEvent(
                    eventIdentifier: identifier,
                    signature: pending.signature
                )
            }
            syncedEvents = updated
            Self.saveMapping(updated, to: mappingFileURL)
            managedEventCount = updated.count
            lastSyncDate = Date()
            lastError = nil
        } catch {
            lastError = "Kalenderabgleich fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func removeAllManagedEvents() async {
        do {
            var removedIdentifiers = Set<String>()
            var didChange = false
            for synced in syncedEvents.values {
                if let event = eventStore.event(withIdentifier: synced.eventIdentifier) {
                    try eventStore.remove(event, span: .thisEvent, commit: false)
                    removedIdentifiers.insert(event.calendarItemIdentifier)
                    didChange = true
                }
            }
            if let calendar = existingManagedCalendar() {
                for event in recoverManagedEvents(in: calendar)
                    .values where !removedIdentifiers.contains(event.calendarItemIdentifier) {
                    try eventStore.remove(event, span: .thisEvent, commit: false)
                    didChange = true
                }
            }
            if didChange {
                try eventStore.commit()
            }
            syncedEvents = [:]
            Self.saveMapping([:], to: mappingFileURL)
            managedEventCount = 0
            lastSyncDate = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Calendar management

    private func ensureManagedCalendar() throws -> EKCalendar {
        if let existing = existingManagedCalendar() {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = Self.calendarTitle
        calendar.source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .local })
            ?? eventStore.sources.first
        guard calendar.source != nil else { throw SyncError.noCalendarSource }
        try eventStore.saveCalendar(calendar, commit: true)
        calendarIdentifier = calendar.calendarIdentifier
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: StoredKeys.calendarIdentifier)
        calendarSourceDescription = Self.sourceDescription(for: calendar)
        return calendar
    }

    private func existingManagedCalendar() -> EKCalendar? {
        if let id = calendarIdentifier,
           let existing = eventStore.calendar(withIdentifier: id),
           existing.title == Self.calendarTitle {
            calendarSourceDescription = Self.sourceDescription(for: existing)
            return existing
        }
        if let found = eventStore.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
            calendarIdentifier = found.calendarIdentifier
            UserDefaults.standard.set(found.calendarIdentifier, forKey: StoredKeys.calendarIdentifier)
            calendarSourceDescription = Self.sourceDescription(for: found)
            return found
        }
        return nil
    }

    private static func sourceDescription(for calendar: EKCalendar) -> String {
        guard let source = calendar.source else { return "Unbekannt" }
        return switch source.sourceType {
        case .local: "Lokal (nur dieser Mac)"
        case .calDAV: "iCloud/CalDAV (\(source.title))"
        case .exchange: "Exchange (\(source.title))"
        case .mobileMe: "iCloud (\(source.title))"
        case .subscribed: "Abonniert (\(source.title))"
        case .birthdays: source.title
        @unknown default: source.title
        }
    }

    // MARK: - Field mapping

    private func apply(entry: FinanceEntry, accounts: [Account], categories: [FinanceCategory], to event: EKEvent, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = "\(entry.title) · \(EntryFormat.signedAmount(entry))"
        event.isAllDay = true
        let isoDate = resolvedDate(for: entry)
        let day = FinanceCalendar.date(isoDate) ?? Date()
        // EventKit treats an all-day event's endDate as exclusive: it must be
        // the day *after* the last day the event spans, or the event covers
        // zero days in Calendar.app.
        let nextDay = FinanceCalendar.date(FinanceCalendar.addingDays(1, to: isoDate)) ?? day
        event.startDate = day
        event.endDate = nextDay
        event.url = managedEventURL(for: entry.id)
        event.notes = notes(for: entry, accounts: accounts, categories: categories)
    }

    private func managedEventURL(for entryID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "meinfinanzplan"
        components.host = "buchung"
        components.path = "/\(entryID)"
        return components.url
    }

    private func recoverManagedEvents(in calendar: EKCalendar) -> [String: EKEvent] {
        let systemCalendar = Calendar(identifier: .gregorian)
        let start = systemCalendar.date(byAdding: .day, value: -Self.horizonDaysBackward - 7, to: Date()) ?? Date()
        let end = systemCalendar.date(byAdding: .day, value: Self.horizonDaysForward + 7, to: Date()) ?? Date()
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        var recovered: [String: EKEvent] = [:]
        for event in eventStore.events(matching: predicate) {
            guard let url = event.url,
                  url.scheme == "meinfinanzplan",
                  url.host == "buchung" else { continue }
            let entryID = String(url.path.drop(while: { $0 == "/" }))
            guard !entryID.isEmpty, recovered[entryID] == nil else { continue }
            recovered[entryID] = event
        }
        return recovered
    }

    /// The date an entry should be shown on: the actual booking date once
    /// known, otherwise the originally planned date.
    private func resolvedDate(for entry: FinanceEntry) -> String {
        entry.actualDate ?? entry.plannedDate
    }

    private func notes(for entry: FinanceEntry, accounts: [Account], categories: [FinanceCategory]) -> String {
        var lines: [String] = []
        if let account = accounts.first(where: { $0.id == entry.accountID }) {
            lines.append("Konto: \(account.name)")
        }
        if let categoryID = entry.categoryID, let category = categories.first(where: { $0.id == categoryID }) {
            lines.append("Kategorie: \(category.name)")
        }
        lines.append("Status: \(entry.status.label)")
        lines.append("Verwaltet von „Mein Finanzplan“ – manuelle Änderungen werden beim nächsten Abgleich überschrieben.")
        return lines.joined(separator: "\n")
    }

    private func signature(for entry: FinanceEntry, accounts: [Account], categories: [FinanceCategory]) -> String {
        let accountName = accounts.first(where: { $0.id == entry.accountID })?.name ?? ""
        let categoryName = categories.first(where: { $0.id == entry.categoryID })?.name ?? ""
        return [entry.title, String(entry.amountCents), entry.kind.rawValue, resolvedDate(for: entry), entry.status.rawValue, accountName, categoryName]
            .joined(separator: "\u{1}")
    }

    // MARK: - Mapping persistence

    private static func loadMapping(from url: URL) -> [String: SyncedEvent] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: SyncedEvent].self, from: data)) ?? [:]
    }

    private static func saveMapping(_ mapping: [String: SyncedEvent], to url: URL) {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func permissionState(from status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess: .authorized
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }
}
