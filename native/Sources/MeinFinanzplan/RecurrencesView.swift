import SwiftUI
import FinanceCore

struct RecurrencesView: View {
    @Environment(AppStore.self) private var store
    @State private var editingRule: RecurringRule?
    @State private var pendingDeletion: RecurringRule?
    @State private var isPresentingNew = false
    @State private var searchText = ""

    private var visibleRules: [RecurringRule] {
        store.snapshot.rules.filter {
            FinanceSearch.matches(
                $0,
                query: searchText,
                accountName: { store.account($0)?.name ?? "" },
                categoryName: { store.category($0)?.name ?? "" }
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(alignment: .center) {
                    Theme.pageTitle("Wiederkehrend")
                    Spacer()
                    FinanceSearchField(text: $searchText, placeholder: "Wiederholungen suchen")
                    Button { isPresentingNew = true } label: {
                        Label("Neue Wiederholung", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .pressable()
                }
                if visibleRules.isEmpty {
                    Card { Text("Noch keine Wiederholungsregeln.").foregroundStyle(Theme.textSecondary) }
                } else {
                    LazyVStack(spacing: Theme.Space.md) {
                        ForEach(visibleRules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
            }
            .padding(Theme.Space.xxl)
        }
        .financeScrollIndicatorsHidden()
        .sheet(item: $editingRule) { rule in
            RuleFormView(rule: rule, accounts: store.snapshot.accounts, categories: store.snapshot.categories) { updated in
                store.updateRecurringRule(updated)
                editingRule = nil
            } onCancel: { editingRule = nil }
        }
        .sheet(isPresented: $isPresentingNew) {
            RuleFormView(rule: nil, accounts: store.snapshot.accounts, categories: store.snapshot.categories) { created in
                store.addRecurringRule(created)
                isPresentingNew = false
            } onCancel: { isPresentingNew = false }
        }
        .alert("Wiederholung löschen?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { rule in
            Button("Löschen", role: .destructive) {
                store.deleteRecurringRule(id: rule.id)
                pendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        } message: { rule in
            Text("„\(rule.title)“ wird dauerhaft aus dem Finanzplan entfernt.")
        }
    }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.sm) {
                            Text(rule.title).font(Theme.sectionHeader)
                            if !rule.isActive { StatusTag(text: "Pausiert", background: Theme.paleYellowBackground, foreground: Theme.paleYellowText) }
                            if rule.isReliable { StatusTag(text: "Verlässlich", background: Theme.paleBlueBackground, foreground: Theme.paleBlueText) }
                        }
                        Text("\(store.account(rule.accountID)?.name ?? "Unbekannt") · \(frequencyLabel(rule))")
                            .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        Text(rangeLabel(rule)).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                        Text(scheduleSummary(rule)).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                        if !rule.amountStages.isEmpty {
                            Text("\(rule.amountStages.count) Betragsstufe(n) geplant").font(Theme.micro).foregroundStyle(Theme.accentStrong)
                        }
                    }
                    Spacer()
                    Text(EntryFormat.signedAmount(cents: rule.amountCents(on: store.snapshot.today), kind: rule.kind))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(EntryFormat.amountColor(kind: rule.kind))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                        .padding(.top, 5)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingRule = rule }
                .help("Zum Bearbeiten klicken")

                Toggle("Aktiv", isOn: Binding(get: { rule.isActive }, set: { store.setRuleActive(id: rule.id, active: $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
                TrashButton(label: "Wiederholung löschen") { pendingDeletion = rule }
            }
        }
        .interactiveRow()
    }

    private func frequencyLabel(_ rule: RecurringRule) -> String {
        rule.interval > 1 ? "alle \(rule.interval) \(rule.frequency.label.lowercased())e Intervalle" : rule.frequency.label
    }

    private func rangeLabel(_ rule: RecurringRule) -> String {
        var text = "ab \(DateText.string(rule.startDate))"
        if let end = rule.endDate { text += " bis \(DateText.string(end))" }
        return text
    }

    private func scheduleSummary(_ rule: RecurringRule) -> String {
        guard rule.frequency == .monthly else { return "" }
        switch rule.schedule {
        case .fixedDay(let day):
            return "Fälligkeitstag \(day.map(String.init) ?? "wie Startdatum")"
        case .dateWindow(let start, let end):
            return "Fenster \(start).–\(end). · \(rule.kind == .income ? "spätester" : "frühester") Tag angesetzt"
        case .weekdayBeforeDeadline(let weekday, let deadline):
            return "\(RuleFormView.weekdayName(weekday)) am/vor dem \(deadline).\(rule.excludedDates.isEmpty ? "" : " · \(rule.excludedDates.count) Ausnahme(n)")"
        case .exactDates(let dates):
            return "\(dates.count) individuell festgelegte Zahlungstermine"
        }
    }
}

private enum ScheduleKindOption: String, CaseIterable, Identifiable, Hashable {
    case fixedDay, dateWindow, weekdayBeforeDeadline, exactDates
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fixedDay: "Fester Kalendertag"
        case .dateWindow: "Datumsfenster"
        case .weekdayBeforeDeadline: "Wochentag vor Stichtag"
        case .exactDates: "Einzelne Termine"
        }
    }
}

struct RuleFormView: View {
    @State private var title: String
    @State private var amount: String
    @State private var kind: EntryKind
    @State private var accountID: String
    @State private var transferAccountID: String
    @State private var categoryID: String
    @State private var frequency: RecurrenceFrequency
    @State private var interval: String
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var scheduleKind: ScheduleKindOption
    @State private var fixedDay: String
    @State private var windowStartDay: String
    @State private var windowEndDay: String
    @State private var weekdaySelection: Int
    @State private var deadlineDay: String
    @State private var excludedDates: [String]
    @State private var newExcludedDate: Date
    @State private var exactDates: [String]
    @State private var newExactDate: Date
    @State private var amountStages: [RecurringAmountStage]
    @State private var isReliable: Bool
    @State private var isActive: Bool

    private let originalID: String?
    private let accounts: [Account]
    private let categories: [FinanceCategory]
    let onSave: (RecurringRule) -> Void
    let onCancel: () -> Void

    static let weekdayOptions: [(Int, String)] = [(2, "Montag"), (3, "Dienstag"), (4, "Mittwoch"), (5, "Donnerstag"), (6, "Freitag"), (7, "Samstag"), (1, "Sonntag")]

    static func weekdayName(_ weekday: Int) -> String {
        weekdayOptions.first { $0.0 == weekday }?.1 ?? "Wochentag"
    }

    init(rule: RecurringRule?, accounts: [Account], categories: [FinanceCategory], onSave: @escaping (RecurringRule) -> Void, onCancel: @escaping () -> Void) {
        _title = State(initialValue: rule?.title ?? "")
        _amount = State(initialValue: rule.map { String(format: "%.2f", Double($0.amountCents) / 100) } ?? "")
        _kind = State(initialValue: rule?.kind ?? .expense)
        _accountID = State(initialValue: rule?.accountID ?? accounts.first?.id ?? "")
        _transferAccountID = State(initialValue: rule?.transferAccountID ?? accounts.dropFirst().first?.id ?? accounts.first?.id ?? "")
        _categoryID = State(initialValue: rule?.categoryID ?? "")
        _frequency = State(initialValue: rule?.frequency ?? .monthly)
        _interval = State(initialValue: String(rule?.interval ?? 1))
        _startDate = State(initialValue: DateText.dateValue(rule?.startDate ?? DateText.string(Date())))
        _hasEndDate = State(initialValue: rule?.endDate != nil)
        _endDate = State(initialValue: DateText.dateValue(rule?.endDate ?? DateText.string(Date())))

        let initialSchedule = rule?.schedule ?? .fixedDay(rule?.dueDay)
        if case .exactDates(let dates) = initialSchedule {
            _exactDates = State(initialValue: dates)
        } else {
            _exactDates = State(initialValue: [])
        }
        switch initialSchedule {
        case .fixedDay(let day):
            _scheduleKind = State(initialValue: .fixedDay)
            _fixedDay = State(initialValue: day.map(String.init) ?? "")
            _windowStartDay = State(initialValue: "1")
            _windowEndDay = State(initialValue: "28")
            _weekdaySelection = State(initialValue: 4)
            _deadlineDay = State(initialValue: "28")
        case .dateWindow(let start, let end):
            _scheduleKind = State(initialValue: .dateWindow)
            _fixedDay = State(initialValue: "")
            _windowStartDay = State(initialValue: String(start))
            _windowEndDay = State(initialValue: String(end))
            _weekdaySelection = State(initialValue: 4)
            _deadlineDay = State(initialValue: "28")
        case .weekdayBeforeDeadline(let weekday, let deadline):
            _scheduleKind = State(initialValue: .weekdayBeforeDeadline)
            _fixedDay = State(initialValue: "")
            _windowStartDay = State(initialValue: "1")
            _windowEndDay = State(initialValue: "28")
            _weekdaySelection = State(initialValue: weekday)
            _deadlineDay = State(initialValue: String(deadline))
        case .exactDates:
            _scheduleKind = State(initialValue: .exactDates)
            _fixedDay = State(initialValue: "")
            _windowStartDay = State(initialValue: "1")
            _windowEndDay = State(initialValue: "28")
            _weekdaySelection = State(initialValue: 4)
            _deadlineDay = State(initialValue: "28")
        }
        _excludedDates = State(initialValue: rule?.excludedDates ?? [])
        _newExcludedDate = State(initialValue: Date())
        _newExactDate = State(initialValue: Date())
        _amountStages = State(initialValue: rule?.amountStages ?? [])
        _isReliable = State(initialValue: rule?.isReliable ?? false)
        _isActive = State(initialValue: rule?.isActive ?? true)
        originalID = rule?.id
        self.accounts = accounts
        self.categories = categories
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var relevantCategories: [FinanceCategory] { categories.filter { $0.kind == kind } }

    var body: some View {
        VStack(spacing: 0) {
            FinanceModalHeader(
                title: originalID == nil ? "Neue Wiederholung" : "Wiederholung bearbeiten",
                subtitle: "Rhythmus, Zeitraum und Zuordnung festlegen",
                systemImage: originalID == nil ? "plus" : "clock.arrow.trianglehead.counterclockwise.rotate.90",
                onClose: onCancel
            )
            Divider().overlay(Theme.border.opacity(0.65))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    EntryKindTabs(selection: $kind)
                    FormMoneyInput(label: "Startbetrag", amount: $amount, kind: kind)
                    FormTextInput(label: "Bezeichnung", icon: "text.alignleft", placeholder: "Zum Beispiel Miete", text: $title)

                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        FormMenuInput(label: "Konto", icon: "wallet.bifold", selection: $accountID, options: accounts.map { ($0.id, $0.name) })
                        FormMenuInput(label: "Kategorie", icon: "tag", selection: $categoryID, options: [("", "Keine Kategorie")] + relevantCategories.map { ($0.id, $0.name) })
                    }

                    if kind == .transfer {
                        FormMenuInput(label: "Zielkonto", icon: "arrow.right.circle", selection: $transferAccountID, options: accounts.map { ($0.id, $0.name) })
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    }

                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        FormMenuInput(label: "Häufigkeit", icon: "repeat", selection: $frequency, options: RecurrenceFrequency.allCases.map { ($0, $0.label) })
                        FormTextInput(label: "Intervall", icon: "number", placeholder: "1", text: $interval)
                    }

                    FormDateInput(label: "Startdatum", icon: "calendar", date: $startDate)

                    if frequency == .monthly {
                        scheduleEditor
                    } else {
                        FormTextInput(label: "Fälligkeitstag (optional)", icon: "calendar.badge.clock", placeholder: "1–31", text: $fixedDay)
                    }

                    FormToggleRow(title: "Enddatum festlegen", subtitle: "Begrenzt die Wiederholung auf einen festen Zeitraum.", icon: "calendar.badge.minus", isOn: $hasEndDate)
                    if hasEndDate {
                        FormDateInput(label: "Enddatum", icon: "calendar.badge.checkmark", date: $endDate)
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                    if kind == .income {
                        FormToggleRow(title: "Verlässliche Einnahme", subtitle: "Wird als sicherer Eingang in der Vorschau berücksichtigt.", icon: "checkmark.shield", isOn: $isReliable)
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                    FormToggleRow(title: "Wiederholung aktiv", subtitle: "Pausierte Regeln erzeugen keine geplanten Buchungen.", icon: "power", isOn: $isActive)

                    amountStagesEditor

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
            FinanceModalFooter(isValid: isValid, onCancel: onCancel, onSave: save)
        }
        .frame(width: 680, height: 900)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .onChange(of: kind) { _, newKind in
            if !relevantCategories.contains(where: { $0.id == categoryID }) { categoryID = "" }
            if newKind != .income { isReliable = false }
        }
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            FormMenuInput(label: "Zahlungstermin", icon: "calendar.day.timeline.left", selection: $scheduleKind, options: ScheduleKindOption.allCases.map { ($0, $0.label) })

            switch scheduleKind {
            case .fixedDay:
                FormTextInput(label: "Kalendertag", icon: "calendar.badge.clock", placeholder: "1–31", text: $fixedDay)
            case .dateWindow:
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    FormTextInput(label: "Fenster ab Tag", icon: "arrow.right.to.line", placeholder: "15", text: $windowStartDay)
                    FormTextInput(label: "Fenster bis Tag", icon: "arrow.left.to.line", placeholder: "25", text: $windowEndDay)
                }
                Text(kind == .income ? "Einnahmen werden konservativ am spätesten Tag des Fensters angesetzt." : "Ausgaben werden konservativ am frühesten Tag des Fensters angesetzt.")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.textSecondary)
            case .weekdayBeforeDeadline:
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    FormMenuInput(label: "Wochentag", icon: "calendar", selection: $weekdaySelection, options: Self.weekdayOptions)
                    FormTextInput(label: "Spätester Kalendertag", icon: "flag.checkered", placeholder: "28", text: $deadlineDay)
                }
                Text("Der letzte passende Wochentag am oder vor dem Stichtag wird verwendet.")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.textSecondary)
                excludedDatesEditor
            case .exactDates:
                exactDatesEditor
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var exactDatesEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Konkrete Zahlungstermine").font(Theme.micro).foregroundStyle(Theme.textSecondary)
            Text("Jeder eingetragene Tag erzeugt genau eine Buchung. Die Liste kann jederzeit um weitere Monate oder Jahre ergänzt werden.")
                .font(Theme.micro)
                .foregroundStyle(Theme.textSecondary)
            ForEach(exactDates, id: \.self) { date in
                HStack {
                    Text(DateText.string(date)).font(Theme.caption)
                    Spacer()
                    TrashButton(label: "Termin entfernen") { exactDates.removeAll { $0 == date } }
                }
                .padding(.horizontal, Theme.Space.sm)
                .frame(height: 30)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: Theme.Space.sm) {
                DatePicker("", selection: $newExactDate, displayedComponents: .date).labelsHidden()
                Button("Termin hinzufügen") {
                    let date = DateText.string(newExactDate)
                    if !exactDates.contains(date) { exactDates.append(date); exactDates.sort() }
                }
                .buttonStyle(.bordered)
                .pressable()
            }
        }
    }

    private var excludedDatesEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Ausnahmetermine (z. B. Feiertage)").font(Theme.micro).foregroundStyle(Theme.textSecondary)
            ForEach(excludedDates, id: \.self) { date in
                HStack {
                    Text(DateText.string(date)).font(Theme.caption)
                    Spacer()
                    TrashButton(label: "Ausnahme entfernen") { excludedDates.removeAll { $0 == date } }
                }
                .padding(.horizontal, Theme.Space.sm)
                .frame(height: 30)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: Theme.Space.sm) {
                DatePicker("", selection: $newExcludedDate, displayedComponents: .date).labelsHidden()
                Text(DateText.shortWeekday(newExcludedDate))
                    .font(Theme.micro)
                    .foregroundStyle(Theme.accentStrong)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
                Button("Ausnahme hinzufügen") {
                    let date = DateText.string(newExcludedDate)
                    if !excludedDates.contains(date) { excludedDates.append(date); excludedDates.sort() }
                }
                .buttonStyle(.bordered)
                .pressable()
            }
        }
    }

    private var amountStagesEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Text("BETRAGSSTUFEN").font(Theme.micro).tracking(1.5).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    amountStages.append(RecurringAmountStage(effectiveDate: DateText.string(Date()), adjustment: .delta(0)))
                } label: {
                    Label("Stufe hinzufügen", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .font(Theme.caption)
                .foregroundStyle(Theme.accent)
                .pressable()
            }
            if amountStages.isEmpty {
                Text("Keine gestaffelten Betragsänderungen. Der Startbetrag gilt dauerhaft.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(amountStages.indices, id: \.self) { index in
                    stageRow(index: index)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stageRow(index: Int) -> some View {
        let dateBinding = Binding<Date>(
            get: { DateText.dateValue(amountStages[index].effectiveDate) },
            set: { amountStages[index].effectiveDate = DateText.string($0) }
        )
        let isAbsoluteBinding = Binding<Bool>(
            get: { if case .absolute = amountStages[index].adjustment { return true } else { return false } },
            set: { newValue in
                let cents = amountStages[index].adjustment.cents
                amountStages[index].adjustment = newValue ? .absolute(cents) : .delta(cents)
            }
        )
        let amountBinding = Binding<String>(
            get: { String(format: "%.2f", Double(amountStages[index].adjustment.cents) / 100) },
            set: { text in
                let cents = Int((Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
                amountStages[index].adjustment = isAbsoluteBinding.wrappedValue ? .absolute(cents) : .delta(cents)
            }
        )
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                DatePicker("Ab", selection: dateBinding, displayedComponents: .date)
                Text(DateText.shortWeekday(dateBinding.wrappedValue))
                    .font(Theme.micro)
                    .foregroundStyle(Theme.accentStrong)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
                Spacer()
                TrashButton(label: "Stufe entfernen") { amountStages.remove(at: index) }
            }
            HStack(spacing: Theme.Space.md) {
                Picker("", selection: isAbsoluteBinding) {
                    Text("Erhöhung/Senkung").tag(false)
                    Text("Neuer Gesamtbetrag").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                TextField("0,00", text: amountBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                Text("€").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
        .padding(Theme.Space.sm)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, (Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0, !accountID.isEmpty else { return false }
        if kind == .transfer, transferAccountID == accountID || transferAccountID.isEmpty { return false }
        if scheduleKind == .dateWindow, frequency == .monthly {
            guard let start = Int(windowStartDay), let end = Int(windowEndDay), start >= 1, end <= 31, start <= end else { return false }
        }
        if scheduleKind == .weekdayBeforeDeadline, frequency == .monthly {
            guard let deadline = Int(deadlineDay), deadline >= 1, deadline <= 31 else { return false }
        }
        if scheduleKind == .exactDates, exactDates.isEmpty { return false }
        return true
    }

    private var resolvedSchedule: RecurrenceSchedule {
        guard frequency == .monthly else { return .fixedDay(Int(fixedDay)) }
        switch scheduleKind {
        case .fixedDay: return .fixedDay(Int(fixedDay))
        case .dateWindow: return .dateWindow(startDay: Int(windowStartDay) ?? 1, endDay: Int(windowEndDay) ?? 28)
        case .weekdayBeforeDeadline: return .weekdayBeforeDeadline(weekday: weekdaySelection, deadlineDay: Int(deadlineDay) ?? 28)
        case .exactDates: return .exactDates(exactDates)
        }
    }

    private func save() {
        let rule = RecurringRule(
            id: originalID ?? UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespaces),
            amountCents: Int((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100),
            kind: kind,
            accountID: accountID,
            transferAccountID: kind == .transfer ? transferAccountID : nil,
            categoryID: categoryID.isEmpty ? nil : categoryID,
            frequency: frequency,
            interval: max(1, Int(interval) ?? 1),
            startDate: DateText.string(startDate),
            endDate: hasEndDate ? DateText.string(endDate) : nil,
            schedule: resolvedSchedule,
            amountStages: amountStages,
            excludedDates: scheduleKind == .weekdayBeforeDeadline ? excludedDates : [],
            isReliable: kind == .income && isReliable,
            isActive: isActive,
            needsReview: false
        )
        onSave(rule)
    }
}
