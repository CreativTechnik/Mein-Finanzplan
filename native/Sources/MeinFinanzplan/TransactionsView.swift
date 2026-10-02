import SwiftUI
import AppKit
import FinanceCore

private enum TransactionFilter: String, CaseIterable, Identifiable {
    case all, income, expense, transfer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Alle"
        case .income: "Einnahmen"
        case .expense: "Ausgaben"
        case .transfer: "Umbuchungen"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        case .transfer: "arrow.left.arrow.right"
        }
    }

    var kind: EntryKind? {
        switch self {
        case .all: nil
        case .income: .income
        case .expense: .expense
        case .transfer: .transfer
        }
    }
}

private enum TransactionCollection: String, CaseIterable, Identifiable {
    case active, archive
    var id: String { rawValue }
    var label: String { self == .active ? "Aktiv" : "Archiv" }
}

struct TransactionsView: View {
    @Environment(AppStore.self) private var store
    @State private var filter: TransactionFilter = .all
    @State private var collection: TransactionCollection = .active
    @State private var editingEntry: FinanceEntry?
    @State private var pendingDeletion: FinanceEntry?
    @State private var isPresentingNew = false
    @State private var searchText = ""
    @State private var onlyWithAttachments = false

    private var filteredEntries: [FinanceEntry] {
        store.snapshot.entries
            .filter { collection == .archive ? $0.isArchived : !$0.isArchived }
            .filter { filter.kind == nil || $0.kind == filter.kind }
            .filter { !onlyWithAttachments || (store.attachmentCounts[$0.id] ?? 0) > 0 }
            .filter {
                FinanceSearch.matches(
                    $0,
                    query: searchText,
                    accountName: { store.account($0)?.name ?? "" },
                    categoryName: { store.category($0)?.name ?? "" }
                )
            }
            .sorted { $0.plannedDate > $1.plannedDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Theme.pageTitle("Buchungen")
                        Text("Planen, prüfen und buchen")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button { isPresentingNew = true } label: {
                        Label("Neue Buchung", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .pressable()
                }

                HStack {
                    TransactionFilterBar(selection: $filter, entries: collectionEntries)
                    Spacer()
                    FinanceSearchField(text: $searchText, placeholder: "Buchungen suchen")
                    Toggle(isOn: $onlyWithAttachments) {
                        Label("Mit Beleg", systemImage: "paperclip")
                    }
                    .toggleStyle(.button)
                    .controlSize(.large)
                    .help("Nur Buchungen mit angehängtem Beleg anzeigen")
                    ChoiceTabs(options: TransactionCollection.allCases, selection: $collection) { $0.label }
                }

                if filteredEntries.isEmpty {
                    Card {
                        HStack(spacing: Theme.Space.md) {
                            IconBadge(systemName: "tray")
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text("Keine passenden Buchungen").font(Theme.sectionHeader)
                                Text("Wähle einen anderen Filter oder lege eine neue Buchung an.")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } else {
                    LazyVStack(spacing: Theme.Space.md) {
                        ForEach(filteredEntries) { entry in
                            transactionRow(entry)
                        }
                    }
                }
            }
            .padding(Theme.Space.xxl)
        }
        .financeScrollIndicatorsHidden()
        .sheet(item: $editingEntry) { entry in
            EntryFormView(entry: entry, accounts: store.snapshot.accounts, categories: store.snapshot.categories) { updated, changes in
                store.saveEntry(updated, isNew: false, newAttachments: changes.newFiles, removedAttachmentIDs: changes.removedIDs)
                editingEntry = nil
            } onCancel: { editingEntry = nil }
        }
        .sheet(isPresented: $isPresentingNew) {
            EntryFormView(entry: nil, accounts: store.snapshot.accounts, categories: store.snapshot.categories) { created, changes in
                store.saveEntry(created, isNew: true, newAttachments: changes.newFiles, removedAttachmentIDs: [])
                isPresentingNew = false
            } onCancel: { isPresentingNew = false }
        }
        .alert("Buchung löschen?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { entry in
            Button("Löschen", role: .destructive) {
                store.deleteEntry(id: entry.id)
                pendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        } message: { entry in
            let receipts = store.attachmentCounts[entry.id] ?? 0
            Text("„\(entry.title)“ wird dauerhaft aus dem Finanzplan entfernt." + (receipts > 0 ? " \(receipts == 1 ? "Der angehängte Beleg wird" : "Die \(receipts) angehängten Belege werden") ebenfalls gelöscht." : ""))
        }
    }

    private var collectionEntries: [FinanceEntry] {
        store.snapshot.entries.filter { collection == .archive ? $0.isArchived : !$0.isArchived }
    }

    private func transactionRow(_ entry: FinanceEntry) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.sm) {
                            Text(entry.title).font(Theme.sectionHeader)
                            statusTag(entry.status)
                            if entry.isReliable {
                                StatusTag(text: "Verlässlich", background: Theme.paleBlueBackground, foreground: Theme.paleBlueText)
                            }
                            if let receipts = store.attachmentCounts[entry.id], receipts > 0 {
                                Label("\(receipts)", systemImage: "paperclip")
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.textSecondary)
                                    .help(receipts == 1 ? "Ein Beleg angehängt" : "\(receipts) Belege angehängt")
                            }
                        }
                        Text(subtitle(entry)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        if let note = entry.note { Text(note).font(Theme.micro).foregroundStyle(Theme.textSecondary) }
                    }
                    Spacer()
                    Text(EntryFormat.signedAmount(entry))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(EntryFormat.amountColor(entry))
                        .padding(.top, 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                        .padding(.top, 5)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingEntry = entry }
                .help("Zum Bearbeiten klicken")

                TrashButton(label: "Buchung löschen") {
                    pendingDeletion = entry
                }
                .padding(.top, -5)
            }
        }
        .interactiveRow()
    }

    private func subtitle(_ entry: FinanceEntry) -> String {
        var parts = [store.account(entry.accountID)?.name ?? "Unbekanntes Konto"]
        if let transferID = entry.transferAccountID, let transferAccount = store.account(transferID) {
            parts.append("→ \(transferAccount.name)")
        }
        if let category = store.category(entry.categoryID) { parts.append(category.name) }
        parts.append(DateText.string(entry.actualDate ?? entry.plannedDate))
        return parts.joined(separator: " · ")
    }

    private func statusTag(_ status: EntryStatus) -> some View {
        switch status {
        case .planned: StatusTag(text: status.label, background: Theme.paleYellowBackground, foreground: Theme.paleYellowText)
        case .booked: StatusTag(text: status.label, background: Theme.paleGreenBackground, foreground: Theme.paleGreenText)
        case .cancelled: StatusTag(text: status.label, background: Theme.paleRedBackground, foreground: Theme.paleRedText)
        }
    }
}

private struct TransactionFilterBar: View {
    @Binding var selection: TransactionFilter
    let entries: [FinanceEntry]

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Label("Ansicht", systemImage: "line.3.horizontal.decrease")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: Theme.Space.xs) {
                ForEach(TransactionFilter.allCases) { item in
                    Button {
                        withAnimation(Theme.Motion.selection) { selection = item }
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.label)
                            Text("\(count(for: item))")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(selection == item ? Color.white.opacity(0.78) : Theme.textSecondary)
                        }
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(selection == item ? Color.white : Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 36)
                        .background(selection == item ? Theme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pressable()
                    .accessibilityLabel("\(item.label), \(count(for: item)) Buchungen")
                }
            }
            .padding(4)
            .background(Theme.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.65), lineWidth: 0.8)
            )
            Spacer()
        }
    }

    private func count(for filter: TransactionFilter) -> Int {
        guard let kind = filter.kind else { return entries.count }
        return entries.lazy.filter { $0.kind == kind }.count
    }
}

struct EntryFormView: View {
    private enum FocusedField { case title, amount, note }

    @Environment(AppStore.self) private var store
    @State private var existingAttachments: [EntryAttachment] = []
    @State private var pendingAttachmentURLs: [URL] = []
    @State private var removedAttachmentIDs: Set<String> = []

    @State private var title: String
    @State private var amount: String
    @State private var kind: EntryKind
    @State private var accountID: String
    @State private var transferAccountID: String
    @State private var categoryID: String
    @State private var plannedDate: Date
    @State private var status: EntryStatus
    @State private var note: String
    @State private var isReliable: Bool
    @FocusState private var focusedField: FocusedField?

    private let originalID: String?
    private let recurrenceID: String?
    private let isArchived: Bool
    private let affectsBalance: Bool
    private let accounts: [Account]
    private let categories: [FinanceCategory]
    let onSave: (FinanceEntry, AttachmentChanges) -> Void
    let onCancel: () -> Void

    init(entry: FinanceEntry?, accounts: [Account], categories: [FinanceCategory], onSave: @escaping (FinanceEntry, AttachmentChanges) -> Void, onCancel: @escaping () -> Void) {
        _title = State(initialValue: entry?.title ?? "")
        _amount = State(initialValue: entry.map { String(format: "%.2f", Double($0.amountCents) / 100) } ?? "")
        _kind = State(initialValue: entry?.kind ?? .expense)
        _accountID = State(initialValue: entry?.accountID ?? accounts.first?.id ?? "")
        _transferAccountID = State(initialValue: entry?.transferAccountID ?? accounts.dropFirst().first?.id ?? accounts.first?.id ?? "")
        _categoryID = State(initialValue: entry?.categoryID ?? "")
        _plannedDate = State(initialValue: DateText.dateValue(entry?.plannedDate ?? DateText.string(Date())))
        _status = State(initialValue: entry?.status ?? .booked)
        _note = State(initialValue: entry?.note ?? "")
        _isReliable = State(initialValue: entry?.isReliable ?? false)
        originalID = entry?.id
        recurrenceID = entry?.recurrenceID
        isArchived = entry?.isArchived ?? false
        affectsBalance = entry?.affectsBalance ?? true
        self.accounts = accounts
        self.categories = categories
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var relevantCategories: [FinanceCategory] { categories.filter { $0.kind == kind } }

    var body: some View {
        VStack(spacing: 0) {
            dialogHeader
            Divider().overlay(Theme.border.opacity(0.65))

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    kindSelector
                    amountComposer
                    textInput(
                        label: "Bezeichnung",
                        icon: "text.alignleft",
                        placeholder: "Zum Beispiel Lebensmittel",
                        text: $title,
                        field: .title
                    )

                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        menuField(
                            label: "Konto",
                            icon: "wallet.bifold",
                            selection: $accountID,
                            options: accounts.map { ($0.id, $0.name) }
                        )
                        menuField(
                            label: "Kategorie",
                            icon: "tag",
                            selection: $categoryID,
                            options: [("", "Keine Kategorie")] + relevantCategories.map { ($0.id, $0.name) }
                        )
                    }

                    if kind == .transfer {
                        menuField(
                            label: "Zielkonto",
                            icon: "arrow.right.circle",
                            selection: $transferAccountID,
                            options: accounts.map { ($0.id, $0.name) }
                        )
                        .transition(.opacity.combined(with: .offset(y: -6)))
                    }

                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        dateField
                        menuField(
                            label: "Status",
                            icon: "checkmark.circle",
                            selection: $status,
                            options: EntryStatus.allCases.map { ($0, $0.label) }
                        )
                    }

                    if kind == .income {
                        Toggle(isOn: $isReliable) {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text("Verlässliche Einnahme").font(Theme.bodyEmphasis)
                                Text("Wird in der Liquiditätsplanung als sicherer Eingang verwendet.")
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                        .padding(Theme.Space.md)
                        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.opacity.combined(with: .offset(y: -6)))
                    }

                    textInput(
                        label: "Notiz",
                        icon: "note.text",
                        placeholder: "Optional",
                        text: $note,
                        field: .note
                    )

                    FormAttachmentsSection(
                        existing: existingAttachments,
                        pendingURLs: $pendingAttachmentURLs,
                        removedIDs: $removedAttachmentIDs
                    ) { attachment in
                        if let url = store.attachmentURL(attachment) {
                            NSWorkspace.shared.open(url)
                        } else {
                            store.errorMessage = "Die Belegdatei „\(attachment.fileName)“ fehlt auf diesem Mac."
                        }
                    }

                    if kind == .transfer && transferAccountID == accountID {
                        Label("Quell- und Zielkonto müssen sich unterscheiden.", systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.paleRedText)
                    }
                }
                .padding(Theme.Space.xl)
            }
            .financeScrollIndicatorsHidden()

            Divider().overlay(Theme.border.opacity(0.65))
            dialogFooter
        }
        .frame(width: 660, height: 700)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .onAppear {
            if let originalID { existingAttachments = store.attachments(for: originalID) }
        }
        .onChange(of: kind) { _, newKind in
            if !relevantCategories.contains(where: { $0.id == categoryID }) { categoryID = "" }
            if newKind != .income { isReliable = false }
        }
    }

    private var dialogHeader: some View {
        HStack(spacing: Theme.Space.md) {
            IconBadge(systemName: originalID == nil ? "plus" : "pencil")
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(originalID == nil ? "Neue Buchung" : "Buchung bearbeiten")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Alle Angaben bleiben lokal auf diesem Mac.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.controlSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .pressable()
            .accessibilityLabel("Schließen")
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: 82)
        .background(Theme.workspace)
    }

    private var kindSelector: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("BUCHUNGSART")
                .font(Theme.micro)
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.xs) {
                ForEach(EntryKind.allCases, id: \.self) { item in
                    Button {
                        withAnimation(Theme.Motion.selection) { kind = item }
                    } label: {
                        Label(item.label, systemImage: kindIcon(item))
                            .font(Theme.bodyEmphasis)
                            .foregroundStyle(kind == item ? Color.white : Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(kind == item ? Theme.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pressable()
                }
            }
            .padding(5)
            .background(Theme.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private var amountComposer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("BETRAG")
                .font(Theme.micro)
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                Text(kind == .expense ? "−" : kind == .income ? "+" : "↔")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(kindColor)
                TextField("0,00", text: $amount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .amount)
                Text("€")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Space.lg)
            .frame(height: 76)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(focusedField == .amount ? Theme.accent : Theme.border.opacity(0.7), lineWidth: focusedField == .amount ? 2 : 0.8)
            )
            .shadow(color: Theme.accent.opacity(focusedField == .amount ? 0.12 : 0), radius: 12)
        }
    }

    private func textInput(label: String, icon: String, placeholder: String, text: Binding<String>, field: FocusedField) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: icon).foregroundStyle(Theme.textSecondary).frame(width: 18)
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(Theme.body)
                    .focused($focusedField, equals: field)
            }
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focusedField == field ? Theme.accent : Theme.border.opacity(0.65), lineWidth: focusedField == field ? 1.5 : 0.8)
            )
        }
    }

    private func menuField<Option: Hashable>(label: String, icon: String, selection: Binding<Option>, options: [(Option, String)]) -> some View {
        let currentLabel = options.first { $0.0 == selection.wrappedValue }?.1 ?? "Auswählen"
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        selection.wrappedValue = option.0
                    } label: {
                        if selection.wrappedValue == option.0 {
                            Label(option.1, systemImage: "checkmark")
                        } else {
                            Text(option.1)
                        }
                    }
                }
            } label: {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: icon).foregroundStyle(Theme.textSecondary).frame(width: 18)
                    Text(currentLabel).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, Theme.Space.md)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.65), lineWidth: 0.8)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Datum").font(Theme.micro).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "calendar").foregroundStyle(Theme.textSecondary).frame(width: 18)
                DatePicker("", selection: $plannedDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(DateText.shortWeekday(plannedDate))
                    .font(Theme.micro)
                    .foregroundStyle(Theme.accentStrong)
                    .frame(minWidth: 30)
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
            }
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.65), lineWidth: 0.8)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var dialogFooter: some View {
        HStack(spacing: Theme.Space.md) {
            Spacer()
            Button("Abbrechen", role: .cancel, action: onCancel)
                .buttonStyle(.plain)
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Space.lg)
                .frame(height: 42)
                .pressable()
            Button(action: save) {
                HStack(spacing: Theme.Space.sm) {
                    Text("Speichern")
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.16), in: Circle())
                }
                .font(Theme.bodyEmphasis)
                .foregroundStyle(.white)
                .padding(.leading, Theme.Space.lg)
                .padding(.trailing, Theme.Space.sm)
                .frame(height: 42)
                .background(isValid ? Theme.accent : Theme.border)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
            .pressable()
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: 72)
        .background(Theme.workspace)
    }

    private var kindColor: Color {
        switch kind {
        case .income: Theme.chartIncome
        case .expense: Theme.chartExpense
        case .transfer: Theme.chartTransfer
        }
    }

    private func kindIcon(_ kind: EntryKind) -> String {
        switch kind {
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        case .transfer: "arrow.left.arrow.right"
        }
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
              (Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0,
              !accountID.isEmpty else { return false }
        if kind == .transfer { return transferAccountID != accountID && !transferAccountID.isEmpty }
        return true
    }

    private func save() {
        let dateString = DateText.string(plannedDate)
        let entry = FinanceEntry(
            id: originalID ?? UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespaces),
            amountCents: Int((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100),
            kind: kind,
            accountID: accountID,
            transferAccountID: kind == .transfer ? transferAccountID : nil,
            categoryID: categoryID.isEmpty ? nil : categoryID,
            recurrenceID: recurrenceID,
            plannedDate: dateString,
            actualDate: status == .booked ? dateString : nil,
            status: status,
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
            isReliable: kind == .income && isReliable,
            affectsBalance: affectsBalance,
            isArchived: isArchived
        )
        onSave(entry, AttachmentChanges(newFiles: pendingAttachmentURLs, removedIDs: Array(removedAttachmentIDs)))
    }
}
