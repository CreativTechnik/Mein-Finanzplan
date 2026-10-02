import SwiftUI
import FinanceCore

struct AccountsView: View {
    @Environment(AppStore.self) private var store
    @State private var editingAccount: Account?
    @State private var pendingDeletion: Account?
    @State private var isPresentingNew = false
    @State private var searchText = ""

    private var visibleAccounts: [Account] {
        store.snapshot.accounts.filter {
            FinanceSearch.matches(searchText, values: [$0.name, $0.kind.label, Money.string($0.currentBalanceCents)])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(alignment: .center) {
                    Theme.pageTitle("Konten")
                    Spacer()
                    FinanceSearchField(text: $searchText, placeholder: "Konten suchen")
                    Button { isPresentingNew = true } label: {
                        Label("Neues Konto", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .pressable()
                }
                LazyVStack(spacing: Theme.Space.md) {
                    ForEach(visibleAccounts) { account in
                        accountRow(account)
                    }
                }
            }
            .padding(Theme.Space.xxl)
        }
        .financeScrollIndicatorsHidden()
        .sheet(item: $editingAccount) { account in
            AccountFormView(account: account) { updated in
                store.updateAccount(updated)
                editingAccount = nil
            } onCancel: { editingAccount = nil }
        }
        .sheet(isPresented: $isPresentingNew) {
            AccountFormView(account: nil) { updated in
                store.addAccount(name: updated.name, kind: updated.kind, balanceCents: updated.currentBalanceCents, bufferCents: updated.minimumBufferCents, colorHex: updated.colorHex, isPrimary: updated.isPrimary)
                isPresentingNew = false
            } onCancel: { isPresentingNew = false }
        }
        .alert("Konto löschen?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { account in
            Button("Konto und Verknüpfungen löschen", role: .destructive) {
                store.deleteAccount(id: account.id)
                pendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        } message: { account in
            Text("„\(account.name)“ sowie damit verknüpfte Buchungen und Wiederholungen werden gelöscht. Mindestens ein Konto bleibt immer erhalten.")
        }
    }

    private func accountRow(_ account: Account) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Circle().fill(Color(hex: account.colorHex)).frame(width: 10, height: 10).padding(.top, 5)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.sm) {
                            Text(account.name).font(Theme.sectionHeader)
                            if account.isPrimary { StatusTag(text: "Primär", background: Theme.paleBlueBackground, foreground: Theme.paleBlueText) }
                            if account.needsReview { StatusTag(text: "Zu prüfen", background: Theme.paleYellowBackground, foreground: Theme.paleYellowText) }
                        }
                        Text("\(account.kind.label) · Stand \(DateText.string(account.balanceAsOf))").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        Text("Mindest-Puffer \(Money.string(account.minimumBufferCents))").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                        Text("Soll-Saldo").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                        Text(Money.string(account.currentBalanceCents))
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(account.currentBalanceCents)))
                            .animation(Theme.Motion.value, value: account.currentBalanceCents)
                        Button {
                            store.confirmAccountBalance(id: account.id)
                        } label: {
                            Label(
                                account.balanceAsOf == store.snapshot.today ? "Heute bestätigt" : "Als Ist bestätigen",
                                systemImage: account.balanceAsOf == store.snapshot.today ? "checkmark.circle.fill" : "circle"
                            )
                        }
                        .buttonStyle(.plain)
                        .font(Theme.micro)
                        .foregroundStyle(account.balanceAsOf == store.snapshot.today ? Theme.paleGreenText : Theme.accentStrong)
                        .disabled(account.balanceAsOf == store.snapshot.today)
                        .help("Bestätigt, dass der berechnete Soll-Saldo mit dem echten Kontostand übereinstimmt.")
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                        .padding(.top, 5)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingAccount = account }
                .help("Zum Bearbeiten klicken")

                TrashButton(label: "Konto löschen") { pendingDeletion = account }
                    .padding(.top, -5)
            }
        }
        .interactiveRow()
    }
}

struct AccountFormView: View {
    @State private var name: String
    @State private var kind: AccountKind
    @State private var balance: String
    @State private var buffer: String
    @State private var isPrimary: Bool
    @State private var balanceAsOf: Date
    @State private var colorHex: String

    private let originalID: String?
    private let needsReview: Bool
    let onSave: (Account) -> Void
    let onCancel: () -> Void

    init(account: Account?, onSave: @escaping (Account) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: account?.name ?? "")
        _kind = State(initialValue: account?.kind ?? .checking)
        _balance = State(initialValue: account.map { String(format: "%.2f", Double($0.currentBalanceCents) / 100) } ?? "")
        _buffer = State(initialValue: account.map { String(format: "%.2f", Double($0.minimumBufferCents) / 100) } ?? "0")
        _isPrimary = State(initialValue: account?.isPrimary ?? false)
        _balanceAsOf = State(initialValue: DateText.dateValue(account?.balanceAsOf ?? DateText.string(Date())))
        _colorHex = State(initialValue: account?.colorHex ?? AccountColorCatalog.colors.first ?? "#4C8D79")
        originalID = account?.id
        needsReview = account?.needsReview ?? false
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            FinanceModalHeader(
                title: originalID == nil ? "Neues Konto" : "Konto bearbeiten",
                subtitle: "Saldo, Puffer und Kontotyp festlegen",
                systemImage: originalID == nil ? "plus" : "wallet.bifold",
                onClose: onCancel
            )
            Divider().overlay(Theme.border.opacity(0.65))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    FormTextInput(label: "Kontoname", icon: "text.alignleft", placeholder: "Zum Beispiel Girokonto", text: $name)
                    FormMenuInput(
                        label: "Kontotyp",
                        icon: "building.columns",
                        selection: $kind,
                        options: AccountKind.allCases.map { ($0, $0.label) }
                    )
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        FormTextInput(label: "Ist-Saldo (€)", icon: "eurosign.circle", placeholder: "0,00", text: $balance)
                        FormTextInput(label: "Mindest-Puffer (€)", icon: "shield", placeholder: "0,00", text: $buffer)
                    }
                    FormDateInput(label: "Saldo-Stichtag", icon: "calendar", date: $balanceAsOf)
                    AccountColorPicker(selection: $colorHex)
                    FormToggleRow(
                        title: "Primäres Konto",
                        subtitle: "Dieses Konto steuert die Liquiditätsvorschau auf der Startseite.",
                        icon: "star.fill",
                        isOn: $isPrimary
                    )
                }
                .padding(Theme.Space.xl)
            }
            .financeScrollIndicatorsHidden()
            Divider().overlay(Theme.border.opacity(0.65))
            FinanceModalFooter(isValid: !name.trimmingCharacters(in: .whitespaces).isEmpty, onCancel: onCancel, onSave: save)
        }
        .frame(width: 620, height: 650)
        .background(Theme.canvas)
        .tint(Theme.accent)
    }

    private func save() {
        let account = Account(
            id: originalID ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            currentBalanceCents: Int((Double(balance.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100),
            balanceAsOf: DateText.string(balanceAsOf),
            minimumBufferCents: Int((Double(buffer.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100),
            colorHex: colorHex,
            isPrimary: isPrimary,
            needsReview: needsReview
        )
        onSave(account)
    }
}

private enum AccountColorCatalog {
    static let colors = [
        "#176FC1", "#2F7594", "#4C82B8", "#6D6FAE",
        "#7A6599", "#4C8D79", "#2B8A73", "#6B8E5E",
        "#A47742", "#B06B4F", "#B45F69", "#7B7F88"
    ]
}

private struct AccountColorPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Diagrammfarbe").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: Theme.Space.xs) {
                    Circle().fill(Color(hex: selection)).frame(width: 10, height: 10)
                    Text(selection).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: Theme.Space.sm) {
                ForEach(AccountColorCatalog.colors, id: \.self) { color in
                    Button {
                        withAnimation(Theme.Motion.selection) { selection = color }
                    } label: {
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 28, height: 28)
                            .padding(3)
                            .overlay {
                                Circle()
                                    .strokeBorder(selection == color ? Theme.textPrimary : Color.clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .pressable()
                    .accessibilityLabel("Diagrammfarbe \(color)")
                }
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
