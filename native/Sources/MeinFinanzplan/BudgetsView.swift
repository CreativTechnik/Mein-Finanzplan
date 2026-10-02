import SwiftUI
import FinanceCore

struct BudgetsView: View {
    @Environment(AppStore.self) private var store
    @State private var drafts: [String: String] = [:]
    @State private var selectedKind: EntryKind = .expense
    @State private var searchText = ""

    private var month: String { String(store.snapshot.today.prefix(7)) }
    private var visibleCategories: [FinanceCategory] {
        store.snapshot.categories
            .filter { $0.kind == selectedKind }
            .filter { FinanceSearch.matches(searchText, values: [$0.name, $0.kind.label]) }
            .sorted { $0.name < $1.name }
    }
    private var monthBudgets: [Budget] { store.snapshot.budgets.filter { $0.month == month } }
    private var visibleCategoryIDs: Set<String> { Set(visibleCategories.map(\.id)) }
    private var visibleBudgets: [Budget] { monthBudgets.filter { visibleCategoryIDs.contains($0.categoryID) } }
    private var totalPlanned: Int { visibleBudgets.reduce(0) { $0 + $1.plannedCents } }
    private var totalActual: Int { visibleBudgets.reduce(0) { $0 + $1.actualCents } }
    private var totalRemaining: Int { totalPlanned - totalActual }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Theme.pageTitle("Budgets")
                            Text("Ausgaben begrenzen, Einnahmen planen und Sparziele verfolgen")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Label(DateText.monthLabel(month), systemImage: "calendar")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.Space.md)
                            .padding(.vertical, Theme.Space.sm)
                            .background(Theme.controlSurface, in: Capsule())
                    }
                    HStack(spacing: Theme.Space.md) {
                        FinanceSearchField(text: $searchText, placeholder: "Budgets suchen")
                        ChoiceTabs(options: EntryKind.allCases, selection: $selectedKind) { budgetKindLabel($0) }
                        Spacer(minLength: 0)
                    }
                }

                budgetOverview

                if visibleCategories.isEmpty {
                    Card {
                        Label("Lege zuerst eine passende Kategorie in den Einstellungen an.", systemImage: "tag")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Theme.Space.lg)], spacing: Theme.Space.lg) {
                        ForEach(visibleCategories) { category in
                            budgetCard(category)
                        }
                    }
                }
            }
            .padding(Theme.Space.xxl)
        }
        .financeScrollIndicatorsHidden()
    }

    private var budgetOverview: some View {
        HeroCard {
            HStack(spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(remainingTitle.uppercased())
                        .font(Theme.micro)
                        .tracking(1.5)
                        .foregroundStyle(Theme.textSecondary)
                    Text(Money.string(totalRemaining))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(overviewValueColor)
                        .contentTransition(.numericText())
                }
                Spacer()
                overviewMetric(goalMetricTitle, totalPlanned, "target")
                Divider().frame(height: 48)
                overviewMetric(actualMetricTitle, totalActual, selectedKind == .transfer ? "arrow.left.arrow.right" : selectedKind == .income ? "arrow.down.left" : "cart")
                DonutRing(progress: totalPlanned > 0 ? Double(totalActual) / Double(totalPlanned) : 0, centerText: percentage(totalActual, totalPlanned))
            }
        }
    }

    private func overviewMetric(_ label: String, _ cents: Int, _ icon: String) -> some View {
        HStack(spacing: Theme.Space.md) {
            IconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                Text(Money.string(cents)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
            }
        }
    }

    private func budget(for categoryID: String) -> Budget? {
        monthBudgets.first { $0.categoryID == categoryID }
    }

    private func budgetCard(_ category: FinanceCategory) -> some View {
        let existing = budget(for: category.id)
        let planned = existing?.plannedCents ?? 0
        let actual = existing?.actualCents ?? 0
        let progress = planned > 0 ? Double(actual) / Double(planned) : 0
        let isOver = selectedKind == .expense && planned > 0 && actual > planned
        let isAchieved = selectedKind != .expense && planned > 0 && actual >= planned
        let draftBinding = Binding<String>(
            get: { drafts[category.id] ?? String(format: "%.2f", Double(planned) / 100) },
            set: { drafts[category.id] = $0 }
        )

        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: category.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentStrong)
                        .frame(width: 38, height: 38)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(category.name).font(Theme.sectionHeader)
                        Text(cardStatusText(planned: planned, actual: actual, isOver: isOver, isAchieved: isAchieved))
                            .font(Theme.micro)
                            .foregroundStyle(isOver ? Theme.paleRedText : Theme.textSecondary)
                    }
                    Spacer()
                    StatusTag(
                        text: percentage(actual, planned),
                        background: isOver ? Theme.paleRedBackground : isAchieved ? Theme.paleGreenBackground : Theme.paleBlueBackground,
                        foreground: isOver ? Theme.paleRedText : isAchieved ? Theme.paleGreenText : Theme.paleBlueText
                    )
                }

                VStack(spacing: Theme.Space.sm) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.controlSurface)
                            Capsule()
                                .fill(isOver ? Theme.chartExpense : isAchieved ? Theme.chartIncome : Theme.accent)
                                .frame(width: geometry.size.width * min(1, max(0, progress)))
                                .animation(Theme.Motion.value, value: progress)
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("\(actualMetricTitle) \(Money.string(actual))")
                        Spacer()
                        Text("von \(Money.string(planned)) \(selectedKind == .expense ? "Budget" : "Ziel")")
                    }
                    .font(Theme.micro)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                }

                HStack(spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "eurosign").foregroundStyle(Theme.textSecondary)
                        TextField("Monatsbudget", text: draftBinding)
                            .textFieldStyle(.plain)
                            .font(Theme.bodyEmphasis)
                            .monospacedDigit()
                            .onSubmit { save(category) }
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .frame(height: 40)
                    .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Button { save(category) } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pressable()
                    .help("Budget speichern")
                }
            }
        }
    }

    private func save(_ category: FinanceCategory) {
        let value = drafts[category.id] ?? ""
        let cents = max(0, Int((Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100))
        store.upsertBudget(month: month, categoryID: category.id, plannedCents: cents)
        drafts[category.id] = nil
    }

    private func percentage(_ actual: Int, _ planned: Int) -> String {
        guard planned > 0 else { return "0 %" }
        return "\(Int((Double(actual) / Double(planned) * 100).rounded())) %"
    }

    private func budgetKindLabel(_ kind: EntryKind) -> String {
        switch kind {
        case .expense: "Ausgaben"
        case .income: "Einnahmen"
        case .transfer: "Sparziele"
        }
    }

    private var remainingTitle: String {
        switch selectedKind {
        case .expense: "Noch verfügbar"
        case .income: "Noch einzuplanen"
        case .transfer: "Noch zu sparen"
        }
    }

    private var goalMetricTitle: String {
        selectedKind == .expense ? "Budget" : "Ziel"
    }

    private var actualMetricTitle: String {
        switch selectedKind {
        case .expense: "Ausgegeben"
        case .income: "Eingenommen"
        case .transfer: "Gespart"
        }
    }

    private var overviewValueColor: Color {
        if selectedKind == .expense && totalRemaining < 0 { return Theme.chartExpense }
        if selectedKind != .expense && totalPlanned > 0 && totalActual >= totalPlanned { return Theme.chartIncome }
        return Theme.accentStrong
    }

    private func cardStatusText(planned: Int, actual: Int, isOver: Bool, isAchieved: Bool) -> String {
        if planned == 0 { return selectedKind == .expense ? "Noch kein Budget" : "Noch kein Ziel" }
        if isOver { return "Budget um \(Money.string(actual - planned)) überschritten" }
        if isAchieved { return "Ziel erreicht" }
        let remaining = max(0, planned - actual)
        return selectedKind == .expense ? "\(Money.string(remaining)) verfügbar" : "\(Money.string(remaining)) fehlen noch"
    }
}
