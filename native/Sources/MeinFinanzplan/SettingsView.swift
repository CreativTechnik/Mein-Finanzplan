import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FinanceCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppLockManager.self) private var appLock
    @State private var selectedCategoryKind: EntryKind = .expense
    @State private var editingCategory: FinanceCategory?
    @State private var isPresentingNewCategory = false
    @State private var backupMessage: String?
    @State private var backupMessageIsError = false
    @State private var pendingImportURL: URL?
    @State private var pendingCategoryDeletion: FinanceCategory?
    @State private var csvSession: CSVImportSession?
    @State private var showingHelpDesk = false
    @State private var showingCodeChange = false
    @State private var categorySearchText = ""
    @State private var isParsingCSV = false
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @AppStorage("menuBarShowAmount") private var menuBarShowAmount = false
    @AppStorage("menuBarHideAmounts") private var menuBarHideAmounts = false

    private var visibleCategories: [FinanceCategory] {
        store.snapshot.categories
            .filter { $0.kind == selectedCategoryKind }
            .filter { FinanceSearch.matches(categorySearchText, values: [$0.name, $0.kind.label]) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Theme.pageTitle("Einstellungen")
                    Text("Darstellung, Kategorien und lokale Datensicherung")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                appearanceCard
                securityCard
                helpDeskCard
                categoriesCard
                calendarSyncCard
                menuBarCard
                backupCard
                storageCard

                HStack {
                    Spacer()
                    VStack(spacing: Theme.Space.xs) {
                        Text("© 2026 CreativTechnik")
                        Text("Version \(appVersion)")
                    }
                    .font(Theme.micro)
                    .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, Theme.Space.md)
            }
            .padding(Theme.Space.xxl)
        }
        .financeScrollIndicatorsHidden()
        .sheet(item: $editingCategory) { category in
            CategoryFormView(category: category, initialKind: category.kind) { updated in
                store.updateCategory(updated)
                editingCategory = nil
            } onCancel: { editingCategory = nil }
        }
        .sheet(isPresented: $showingHelpDesk) {
            FinanceLogicGuide(onClose: { showingHelpDesk = false })
        }
        .sheet(isPresented: $showingCodeChange) {
            ChangeAppCodeView(onClose: { showingCodeChange = false })
        }
        .sheet(isPresented: $isPresentingNewCategory) {
            CategoryFormView(category: nil, initialKind: selectedCategoryKind) { created in
                store.addCategory(name: created.name, kind: created.kind, iconName: created.iconName)
                selectedCategoryKind = created.kind
                isPresentingNewCategory = false
            } onCancel: { isPresentingNewCategory = false }
        }
        .sheet(item: $csvSession) { session in
            CSVImportReviewView(session: session, accounts: store.snapshot.accounts, categories: store.snapshot.categories) { entries in
                store.errorMessage = nil
                if let count = store.importBankEntries(entries) {
                    let skipped = entries.count - count
                    backupMessage = skipped > 0
                        ? "\(count) Bankbuchungen importiert, \(skipped) als Duplikat übersprungen."
                        : "\(count) Bankbuchungen importiert."
                    backupMessageIsError = false
                    csvSession = nil
                } else {
                    backupMessage = store.errorMessage ?? "CSV-Import fehlgeschlagen."
                    backupMessageIsError = true
                }
            } onCancel: { csvSession = nil }
        }
        .alert("Datensicherung importieren?", isPresented: Binding(
            get: { pendingImportURL != nil },
            set: { if !$0 { pendingImportURL = nil } }
        ), presenting: pendingImportURL) { url in
            Button("Importieren", role: .destructive) { importJSON(url) }
            Button("Abbrechen", role: .cancel) { pendingImportURL = nil }
        } message: { url in
            Text("„\(url.lastPathComponent)“ ersetzt alle aktuellen Daten. Vorher wird automatisch eine Wiederherstellungsdatei angelegt.")
        }
        .alert("Kategorie löschen?", isPresented: Binding(
            get: { pendingCategoryDeletion != nil },
            set: { if !$0 { pendingCategoryDeletion = nil } }
        ), presenting: pendingCategoryDeletion) { category in
            Button("Löschen", role: .destructive) {
                store.deleteCategory(id: category.id)
                pendingCategoryDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { pendingCategoryDeletion = nil }
        } message: { category in
            Text("„\(category.name)“ wird gelöscht. Vorhandene Buchungen bleiben erhalten und werden auf „Ohne Kategorie“ gesetzt.")
        }
    }

    private var appearanceCard: some View {
        Card {
            HStack(spacing: Theme.Space.xl) {
                IconBadge(systemName: "circle.lefthalf.filled")
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Erscheinungsbild").font(Theme.sectionHeader)
                    Text("System folgt automatisch der Darstellung von macOS.")
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Picker("Erscheinungsbild", selection: $appearance) {
                    Text("Hell").tag("light")
                    Text("Dunkel").tag("dark")
                    Text("System").tag("system")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
    }

    private var securityCard: some View {
        Card {
            HStack(spacing: Theme.Space.xl) {
                IconBadge(systemName: "lock.shield")
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("App-Schutz").font(Theme.sectionHeader)
                    Text(appLock.hasCustomCode ? "Eigener Code im macOS-Schlüsselbund" : "Standardcode 2026 aktiv")
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Jetzt sperren") { appLock.lock() }.buttonStyle(.bordered)
                Button("Code ändern") { showingCodeChange = true }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
    }

    private var helpDeskCard: some View {
        Card {
            HStack(spacing: Theme.Space.xl) {
                IconBadge(systemName: "lifepreserver")
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Help Desk").font(Theme.sectionHeader)
                    Text("Anleitungen zu Konten, Buchungen, Planung, Import, Berichten und Sicherheit.")
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Anleitung öffnen") { showingHelpDesk = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var categoriesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Kategorien").font(Theme.sectionHeader)
                        Text("Ordne Buchungen schneller und einheitlich zu.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button { isPresentingNewCategory = true } label: {
                        Label("Neue Kategorie", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .pressable()
                }
                HStack(spacing: Theme.Space.md) {
                    FinanceSearchField(text: $categorySearchText, placeholder: "Kategorien suchen")
                    ChoiceTabs(options: EntryKind.allCases, selection: $selectedCategoryKind) { $0.label }
                    Spacer(minLength: 0)
                }

                if visibleCategories.isEmpty {
                    Text("Noch keine Kategorien dieser Art.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, Theme.Space.md)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: Theme.Space.sm)], spacing: Theme.Space.sm) {
                        ForEach(visibleCategories) { category in
                            HStack(spacing: 0) {
                                Button {
                                    editingCategory = category
                                } label: {
                                HStack(spacing: Theme.Space.sm) {
                                    Image(systemName: category.iconName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(categoryColor)
                                        .frame(width: 28, height: 28)
                                        .background(categoryColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    Text(category.name).font(Theme.body).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.leading, Theme.Space.sm)
                                .frame(height: 42)
                                }
                                .buttonStyle(.plain)
                                .pressable()
                                .help("Name und Symbol bearbeiten")
                                TrashButton(label: "Kategorie löschen") { pendingCategoryDeletion = category }
                            }
                            .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var calendarSyncCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                FormToggleRow(
                    title: "Apple-Kalender-Synchronisierung",
                    subtitle: calendarSyncSubtitle,
                    icon: "calendar.badge.clock",
                    isOn: Binding(
                        get: { store.calendarSync.isEnabled },
                        set: { newValue in
                            Task {
                                await store.calendarSync.setEnabled(newValue)
                                store.triggerAppleCalendarSync()
                            }
                        }
                    )
                )
                .disabled(store.calendarSync.isRequestingAccess)

                Text("Spiegelt Buchungen und Wiederholungen der letzten \(AppleCalendarSyncManager.horizonDaysBackward) und kommenden \(AppleCalendarSyncManager.horizonDaysForward) Tage in den eigenen Kalender „\(AppleCalendarSyncManager.calendarTitle)“. Andere Kalender bleiben unberührt. Bei iCloud oder Exchange übernimmt Apple die Weitergabe auf deine Geräte.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let source = store.calendarSync.calendarSourceDescription, store.calendarSync.permissionState == .authorized {
                    Label("Kalenderquelle: \(source)", systemImage: "icloud")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.textSecondary)
                }

                if !store.calendarSync.isEnabled {
                    Label("Ausgeschaltet – es werden keine Kalenderdaten verändert.", systemImage: "calendar.badge.minus")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else if store.calendarSync.isRequestingAccess {
                    HStack(spacing: Theme.Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Warte auf die Kalenderfreigabe von macOS …")
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                } else if store.calendarSync.permissionState == .writeOnly {
                    HStack(spacing: Theme.Space.md) {
                        Label("Nur Schreibzugriff erteilt – Vollzugriff nötig, um eigene Ereignisse zu lesen und zu entfernen.", systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.paleRedText)
                        Spacer()
                        Button("Vollzugriff anfragen") {
                            Task {
                                await store.calendarSync.requestAccessUpgrade()
                                store.triggerAppleCalendarSync()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if store.calendarSync.permissionState == .denied {
                    HStack(spacing: Theme.Space.md) {
                        Label("macOS blockiert den Kalenderzugriff. Erlaube „Mein Finanzplan“ unter Datenschutz & Sicherheit → Kalender; danach startet der Abgleich automatisch.", systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.paleRedText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Zugriff erlauben") {
                            AppleCalendarSyncManager.openCalendarPrivacySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                } else if store.calendarSync.permissionState == .restricted {
                    Label("Eine Systemrichtlinie verhindert den Kalenderzugriff.", systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.paleRedText)
                } else if let lastError = store.calendarSync.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.paleRedText)
                        .textSelection(.enabled)
                } else if store.calendarSync.isSyncing {
                    HStack(spacing: Theme.Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Kalender wird abgeglichen …")
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                } else if let lastSyncDate = store.calendarSync.lastSyncDate {
                    HStack(spacing: Theme.Space.md) {
                        Label {
                            Text("Zuletzt abgeglichen: ") + Text(lastSyncDate, style: .relative) + Text(" · \(store.calendarSync.managedEventCount) Ereignisse")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Spacer()
                        Button("Jetzt abgleichen") { store.triggerAppleCalendarSync() }
                            .buttonStyle(.bordered)
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.paleGreenText)
                } else if store.calendarSync.permissionState == .authorized {
                    HStack(spacing: Theme.Space.md) {
                        Label("Kalenderzugriff erteilt – bereit für den ersten Abgleich.", systemImage: "checkmark.circle.fill")
                        Spacer()
                        Button("Jetzt abgleichen") { store.triggerAppleCalendarSync() }
                            .buttonStyle(.bordered)
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.paleGreenText)
                }
            }
        }
    }

    private var menuBarCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                FormToggleRow(
                    title: "Menüleisten-Symbol",
                    subtitle: "Zeigt frei verfügbaren Betrag und nächste Buchungen per Klick in der Menüleiste.",
                    icon: "menubar.rectangle",
                    isOn: $menuBarEnabled
                )
                FormToggleRow(
                    title: "Betrag in der Menüleiste",
                    subtitle: "Aus: nur das Symbol ist sichtbar, Beträge erscheinen erst im Fenster.",
                    icon: "eurosign.circle",
                    isOn: $menuBarShowAmount
                )
                .disabled(!menuBarEnabled)
                FormToggleRow(
                    title: "Beträge verbergen",
                    subtitle: "Ersetzt Beträge und Titel durch Platzhalter, etwa bei Bildschirmfreigabe.",
                    icon: "eye.slash",
                    isOn: $menuBarHideAmounts
                )
                .disabled(!menuBarEnabled)
                Text("Bei gesperrter App zeigt die Menüleiste weder Beträge noch Titel. Nach dem Entsperren bleibt die App bis zum Beenden entsperrt; mit „Sperren“ im Fenster sperrst du sie wieder.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calendarSyncSubtitle: String {
        if !store.calendarSync.isEnabled {
            return "Aus – beim Aktivieren fragt macOS nach Vollzugriff."
        }
        if store.calendarSync.isRequestingAccess {
            return "Kalenderfreigabe wird angefragt …"
        }
        if store.calendarSync.isSyncing {
            return "Abgleich läuft …"
        }
        return switch store.calendarSync.permissionState {
        case .notDetermined: "Beim Aktivieren fragt macOS einmalig nach Kalenderzugriff."
        case .authorized: "Läuft automatisch bei jeder Aktualisierung im Hintergrund."
        case .writeOnly: "Nur Schreibzugriff erteilt – Vollzugriff erforderlich."
        case .denied: "Zugriff verweigert – in den Systemeinstellungen erlauben."
        case .restricted: "Zugriff ist durch eine Systemrichtlinie eingeschränkt."
        }
    }

    private var backupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Datensicherung").font(Theme.sectionHeader)
                    Text("Alle Konten, Kategorien, Buchungen, Wiederholungen und Budgets in einer lokalen JSON-Datei. Belegdateien sind nicht enthalten.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: Theme.Space.md) {
                    backupAction(
                        title: "Sicherung exportieren",
                        subtitle: "Aktuellen Stand speichern",
                        icon: "arrow.up.doc",
                        action: exportJSON
                    )
                    backupAction(
                        title: "Sicherung importieren",
                        subtitle: "Vorhandenen Stand wiederherstellen",
                        icon: "arrow.down.doc",
                        action: chooseImport
                    )
                    backupAction(
                        title: "Kontoauszug importieren",
                        subtitle: "CSV prüfen und zuordnen",
                        icon: "tablecells",
                        action: chooseCSV
                    )
                }

                if let backupMessage {
                    Label(backupMessage, systemImage: backupMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(backupMessageIsError ? Theme.paleRedText : Theme.paleGreenText)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func backupAction(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title).font(Theme.bodyEmphasis).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .pressable()
    }

    private var storageCard: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                IconBadge(systemName: "internaldrive")
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Lokaler Speicherort").font(Theme.sectionHeader)
                    Text(store.databaseFileURL?.path ?? "Unbekannt")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                    if let folder = store.attachmentFolderURL {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text("Belege").font(Theme.bodyEmphasis)
                            Text(folder.path)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                            HStack(spacing: Theme.Space.md) {
                                Text(attachmentSummary)
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.textSecondary)
                                Button("Im Finder zeigen") {
                                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Text("Belege liegen unverschlüsselt in diesem Ordner. Die JSON-Sicherung enthält nur die Zuordnung, nicht die Dateien – sichere den Ordner „Belege“ zusätzlich.")
                                .font(Theme.micro)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Label("Keine Cloud, kein Webserver, kein Online-Konto", systemImage: "lock.fill")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.paleBlueText)
                }
            }
        }
    }

    private var attachmentSummary: String {
        let count = store.attachmentCounts.values.reduce(0, +)
        let size = ByteCountFormatter.string(fromByteCount: Int64(store.attachmentTotalBytes), countStyle: .file)
        return count == 0 ? "Noch keine Belege angehängt." : "\(count) Belege angehängt · \(size)"
    }

    private var categoryColor: Color {
        switch selectedCategoryKind {
        case .income: Theme.chartIncome
        case .expense: Theme.chartExpense
        case .transfer: Theme.chartTransfer
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Entwicklung"
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "finanzplan-\(store.snapshot.today).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.errorMessage = nil
        store.exportData(to: url)
        if let error = store.errorMessage {
            backupMessage = error
            backupMessageIsError = true
        } else {
            backupMessage = "Sicherung gespeichert: \(url.lastPathComponent)"
            backupMessageIsError = false
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Wähle eine Mein-Finanzplan-Sicherung im JSON-Format."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingImportURL = url
    }

    private func chooseCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Wähle einen CSV-Kontoauszug. Die Daten werden vor dem Import geprüft."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isParsingCSV = true
        backupMessage = "Kontoauszug wird im Hintergrund geprüft …"
        backupMessageIsError = false
        Task {
            do {
                let rows = try await Task.detached(priority: .userInitiated) {
                    try BankCSVParser.parse(data: Data(contentsOf: url))
                }.value
                csvSession = CSVImportSession(
                    sourceName: url.lastPathComponent,
                    rows: rows,
                    existingEntries: store.snapshot.entries,
                    knownFingerprints: store.bankImportFingerprints()
                )
                backupMessage = nil
            } catch {
                backupMessage = error.localizedDescription
                backupMessageIsError = true
            }
            isParsingCSV = false
        }
    }

    private func importJSON(_ url: URL) {
        pendingImportURL = nil
        store.errorMessage = nil
        if let recoveryURL = store.importData(from: url) {
            let missing = store.missingAttachmentFileCount()
            backupMessage = "Import abgeschlossen. Alter Stand gesichert als \(recoveryURL.lastPathComponent)."
                + (missing > 0 ? " \(missing) Belegdatei\(missing == 1 ? " fehlt" : "en fehlen") auf diesem Mac; kopiere den Ordner „Belege“ dorthin." : "")
            backupMessageIsError = false
        } else {
            backupMessage = store.errorMessage ?? "Die Sicherung konnte nicht importiert werden."
            backupMessageIsError = true
        }
    }
}

private enum CategoryIconCatalog {
    static let icons = [
        "tag", "house", "cart", "fork.knife", "basket", "cup.and.saucer",
        "car", "tram", "ticket", "fuelpump", "bicycle", "airplane",
        "tshirt", "bag", "shippingbox", "gift", "sparkles", "gamecontroller",
        "heart", "cross.case", "pills", "figure.walk", "figure.run", "pawprint",
        "iphone", "wifi", "bolt", "drop", "flame", "key",
        "building.columns", "creditcard", "banknote", "eurosign.circle", "banknote.fill", "calendar",
        "repeat", "tv", "book", "graduationcap", "hammer", "wrench.and.screwdriver"
    ]
}

private struct CategoryFormView: View {
    @State private var name: String
    @State private var kind: EntryKind
    @State private var iconName: String

    private let originalID: String?
    let onSave: (FinanceCategory) -> Void
    let onCancel: () -> Void

    init(category: FinanceCategory?, initialKind: EntryKind, onSave: @escaping (FinanceCategory) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: category?.name ?? "")
        _kind = State(initialValue: category?.kind ?? initialKind)
        _iconName = State(initialValue: category?.iconName ?? "tag")
        originalID = category?.id
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            FinanceModalHeader(
                title: originalID == nil ? "Neue Kategorie" : "Kategorie bearbeiten",
                subtitle: "Name, Buchungsart und eigenes Symbol festlegen",
                systemImage: iconName,
                onClose: onCancel
            )
            Divider().overlay(Theme.border.opacity(0.65))

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    FormTextInput(label: "Kategoriename", icon: "text.alignleft", placeholder: "Zum Beispiel Kaution", text: $name)
                    EntryKindTabs(selection: $kind)
                        .disabled(originalID != nil)
                    if originalID != nil {
                        Label("Die Buchungsart bleibt beim Bearbeiten erhalten, damit vorhandene Buchungen korrekt zugeordnet bleiben.", systemImage: "info.circle")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack {
                            Text("SYMBOL").font(Theme.micro).tracking(1.5).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Label("Ausgewählt", systemImage: iconName)
                                .font(Theme.micro)
                                .foregroundStyle(Theme.accentStrong)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.sm), count: 7), spacing: Theme.Space.sm) {
                            ForEach(CategoryIconCatalog.icons, id: \.self) { icon in
                                Button {
                                    withAnimation(Theme.Motion.selection) { iconName = icon }
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(iconName == icon ? Color.white : Theme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(iconName == icon ? Theme.accent : Theme.controlSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .pressable()
                                .accessibilityLabel("Symbol \(icon)")
                            }
                        }
                    }
                }
                .padding(Theme.Space.xl)
            }
            .financeScrollIndicatorsHidden()

            Divider().overlay(Theme.border.opacity(0.65))
            FinanceModalFooter(
                isValid: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: onCancel,
                onSave: save
            )
        }
        .frame(width: 650, height: 660)
        .background(Theme.canvas)
        .tint(Theme.accent)
    }

    private func save() {
        onSave(FinanceCategory(
            id: originalID ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            iconName: iconName
        ))
    }
}
