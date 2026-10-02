import SwiftUI
import FinanceCore

struct CSVImportSession: Identifiable {
    let id = UUID()
    let sourceName: String
    let rows: [ParsedBankRow]
    var existingEntries: [FinanceEntry] = []
    var knownFingerprints: Set<String> = []
}

private struct CSVImportDraft: Identifiable {
    let id: UUID
    let fingerprint: String
    let originalTitle: String
    var isSelected = true
    var date: String
    var title: String
    var signedAmountCents: Int
    var kind: EntryKind
    var accountID: String
    var counterAccountID: String = ""
    var categoryID: String = ""
    var duplicate: ImportDuplicateMatch?

    private var isIncomingTransfer: Bool { kind == .transfer && signedAmountCents >= 0 }

    func entry(title: String) -> BankImportEntry {
        BankImportEntry(
            title: title,
            amountCents: abs(signedAmountCents),
            kind: kind,
            accountID: isIncomingTransfer ? counterAccountID : accountID,
            transferAccountID: kind == .transfer ? (isIncomingTransfer ? accountID : counterAccountID) : nil,
            categoryID: kind == .transfer || categoryID.isEmpty ? nil : categoryID,
            date: date,
            fingerprint: fingerprint
        )
    }
}

struct CSVImportReviewView: View {
    @State private var drafts: [CSVImportDraft]
    let session: CSVImportSession
    let accounts: [Account]
    let categories: [FinanceCategory]
    let onImport: ([BankImportEntry]) -> Void
    let onCancel: () -> Void
    private let existingByID: [String: FinanceEntry]

    init(session: CSVImportSession, accounts: [Account], categories: [FinanceCategory], onImport: @escaping ([BankImportEntry]) -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.accounts = accounts
        self.categories = categories
        existingByID = Dictionary(session.existingEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let firstAccount = accounts.first(where: \.isPrimary)?.id ?? accounts.first?.id ?? ""
        var initial = session.rows.map {
            CSVImportDraft(
                id: $0.id,
                fingerprint: $0.fingerprint,
                originalTitle: $0.title,
                date: $0.date,
                title: $0.title,
                signedAmountCents: $0.signedAmountCents,
                kind: $0.signedAmountCents >= 0 ? .income : .expense,
                accountID: firstAccount,
                counterAccountID: accounts.first(where: { $0.id != firstAccount })?.id ?? ""
            )
        }
        let matches = ImportDuplicateDetector.detect(initial.map { $0.entry(title: $0.originalTitle) }, existing: session.existingEntries, knownFingerprints: session.knownFingerprints)
        for index in initial.indices {
            initial[index].duplicate = matches[index]
            if matches[index]?.level == .certain { initial[index].isSelected = false }
        }
        _drafts = State(initialValue: initial)
        self.onImport = onImport
        self.onCancel = onCancel
    }

    private var selectedCount: Int { drafts.filter(\.isSelected).count }
    private var certainDrafts: [CSVImportDraft] { drafts.filter { $0.duplicate?.level == .certain } }
    private var possibleDrafts: [CSVImportDraft] { drafts.filter { $0.duplicate?.level == .possible } }
    private var matchSignature: [String] {
        drafts.map { "\($0.accountID)|\($0.kind.rawValue)|\($0.counterAccountID)" }
    }

    var body: some View {
        VStack(spacing: 0) {
            FinanceModalHeader(title: "Kontoauszug prüfen", subtitle: "\(session.sourceName) · \(drafts.count) erkannte Zeilen", systemImage: "tablecells", onClose: onCancel)
            Divider().overlay(Theme.border.opacity(0.65))
            HStack(spacing: Theme.Space.md) {
                Toggle("Alle auswählen", isOn: Binding(get: { selectedCount == drafts.count }, set: { value in
                    for index in drafts.indices { drafts[index].isSelected = value }
                }))
                .toggleStyle(.checkbox)
                Spacer()
                Text("Beträge werden als gebucht importiert; der aktuelle Kontostand bleibt unverändert.")
                    .font(Theme.micro).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Space.xl).frame(height: 50).background(Theme.workspace)
            if !certainDrafts.isEmpty || !possibleDrafts.isEmpty {
                duplicateBar
            }

            ScrollView {
                LazyVStack(spacing: Theme.Space.sm) {
                    ForEach($drafts) { $draft in
                        row($draft)
                    }
                }
                .padding(Theme.Space.xl)
            }
            .financeScrollIndicatorsHidden()
            Divider().overlay(Theme.border.opacity(0.65))
            FinanceModalFooter(
                isValid: selectedCount > 0 && drafts.filter(\.isSelected).allSatisfy(isValid),
                onCancel: onCancel,
                onSave: importSelected,
                saveTitle: "\(selectedCount) importieren"
            )
        }
        .frame(width: 1160, height: 720)
        .background(Theme.canvas)
        .onChange(of: matchSignature) { _, _ in recomputeDuplicates() }
    }

    private var duplicateBar: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "doc.on.doc").foregroundStyle(Theme.paleYellowText)
            Text("\(certainDrafts.count) bereits vorhanden · \(possibleDrafts.count) mögliche Duplikate")
                .font(Theme.caption).foregroundStyle(Theme.textPrimary)
            Spacer()
            if !certainDrafts.isEmpty {
                let anySelected = certainDrafts.contains(where: \.isSelected)
                Button(anySelected ? "Vorhandene abwählen" : "Vorhandene trotzdem wählen") {
                    setSelection(!anySelected, for: .certain)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            if !possibleDrafts.isEmpty {
                let anySelected = possibleDrafts.contains(where: \.isSelected)
                Button(anySelected ? "Mögliche abwählen" : "Mögliche wieder wählen") {
                    setSelection(!anySelected, for: .possible)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Space.xl).frame(height: 42)
        .background(Theme.paleYellowBackground.opacity(0.6))
    }

    private func setSelection(_ value: Bool, for level: ImportDuplicateMatch.Level) {
        for index in drafts.indices where drafts[index].duplicate?.level == level {
            drafts[index].isSelected = value
        }
    }

    private func recomputeDuplicates() {
        let matches = ImportDuplicateDetector.detect(drafts.map { $0.entry(title: $0.originalTitle) }, existing: session.existingEntries, knownFingerprints: session.knownFingerprints)
        for index in drafts.indices {
            let wasCertain = drafts[index].duplicate?.level == .certain
            let isCertain = matches[index]?.level == .certain
            drafts[index].duplicate = matches[index]
            if isCertain && !wasCertain { drafts[index].isSelected = false }
            if !isCertain && wasCertain { drafts[index].isSelected = true }
        }
    }

    private func duplicateBadge(for match: ImportDuplicateMatch) -> some View {
        Group {
            switch match.level {
            case .certain:
                StatusTag(text: "Bereits vorhanden", background: Theme.paleBlueBackground, foreground: Theme.paleBlueText)
            case .possible:
                StatusTag(text: "Mögliches Duplikat", background: Theme.paleYellowBackground, foreground: Theme.paleYellowText)
            }
        }
        .help(duplicateExplanation(for: match))
    }

    private func duplicateExplanation(for match: ImportDuplicateMatch) -> String {
        guard let id = match.entryID, let entry = existingByID[id] else {
            return "Diese Zeile wurde bereits aus einem früheren Kontoauszug importiert."
        }
        let prefix = match.level == .certain ? "Gleiche Buchung" : "Ähnliche Buchung (gleicher Betrag, Konto und Art)"
        return "\(prefix): „\(entry.title)“ am \(DateText.string(entry.actualDate ?? entry.plannedDate)) · \(entry.status.label)"
    }

    private func row(_ draft: Binding<CSVImportDraft>) -> some View {
        let kind = draft.wrappedValue.kind
        let relevant = categories.filter { $0.kind == kind }
        let duplicate = draft.wrappedValue.duplicate
        return HStack(spacing: Theme.Space.md) {
            Toggle("", isOn: draft.isSelected).labelsHidden().toggleStyle(.checkbox)
            Text(DateText.string(draft.wrappedValue.date)).font(Theme.micro).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
            TextField("Bezeichnung", text: draft.title).textFieldStyle(.plain)
                .padding(.leading, 10).padding(.trailing, duplicate == nil ? 10 : 126)
                .frame(height: 36)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous)).frame(minWidth: 250)
                .overlay(alignment: .trailing) {
                    if let duplicate { duplicateBadge(for: duplicate).padding(.trailing, 8) }
                }
            Picker("Art", selection: draft.kind) {
                ForEach(EntryKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            Picker("Konto", selection: draft.accountID) { ForEach(accounts) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 155)
            if kind == .transfer {
                Picker(draft.wrappedValue.signedAmountCents >= 0 ? "Quellkonto" : "Zielkonto", selection: draft.counterAccountID) {
                    ForEach(accounts.filter { $0.id != draft.wrappedValue.accountID }) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 155)
            } else {
                Picker("Kategorie", selection: draft.categoryID) {
                    Text("Ohne Kategorie").tag("")
                    ForEach(relevant) { Label($0.name, systemImage: $0.iconName).tag($0.id) }
                }.labelsHidden().frame(width: 175)
            }
            Text(Money.string(abs(draft.wrappedValue.signedAmountCents)))
                .font(Theme.bodyEmphasis).monospacedDigit()
                .foregroundStyle(kind == .income ? Theme.chartIncome : Theme.chartExpense)
                .frame(width: 100, alignment: .trailing)
        }
        .opacity(draft.wrappedValue.isSelected ? 1 : 0.45)
        .padding(.horizontal, Theme.Space.md).frame(height: 54)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func importSelected() {
        onImport(drafts.filter(\.isSelected).map {
            $0.entry(title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    private func isValid(_ draft: CSVImportDraft) -> Bool {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.accountID.isEmpty else { return false }
        if draft.kind == .transfer {
            return !draft.counterAccountID.isEmpty && draft.counterAccountID != draft.accountID
        }
        return true
    }
}
