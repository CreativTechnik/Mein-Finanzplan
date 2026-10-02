import SwiftUI
import Charts
import FinanceCore

private struct DashboardChartPoint: Identifiable, Hashable {
    let date: String
    let dateValue: Date
    let accountID: String
    let balanceCents: Int
    var id: String { "\(date):\(accountID)" }
}

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var period: CalendarPeriod = CalendarPeriodEngine.period(kind: .month, containing: FinanceCalendar.today())
    @State private var selectedDate: Date?
    @State private var selectedUpcomingEntry: FinanceEntry?
    @State private var focusedAccountID: String?
    @State private var yZoom: Double = 1
    @GestureState private var liveYMagnification: CGFloat = 1
    @State private var chartPoints: [DashboardChartPoint] = []
    @State private var chartMarkers: [DashboardChartPoint] = []
    @State private var chartPointsByAccount: [String: [DashboardChartPoint]] = [:]
    @State private var upcomingEntries: [FinanceEntry] = []
    @State private var searchText = ""

    let onOpenStatistics: () -> Void

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var primaryAccount: Account? { snapshot.accounts.first { $0.isPrimary } ?? snapshot.accounts.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                if let liquidity = snapshot.liquidity, let account = primaryAccount {
                    HStack(alignment: .top, spacing: Theme.Space.lg) {
                        availableAmountCard(liquidity: liquidity, account: account)
                            .frame(maxWidth: .infinity, minHeight: 264)
                        VStack(spacing: Theme.Space.lg) {
                            weekRingCard(liquidity: liquidity, account: account)
                            nextIncomeCard(liquidity: liquidity)
                        }
                        .frame(width: 310)
                    }
                } else {
                    Card { Text("Noch kein primäres Konto vorhanden.").foregroundStyle(Theme.textSecondary) }
                }
                forecastCard
                upcomingCard
            }
            .padding(Theme.Space.xxl)
        }
        .financeScrollIndicatorsHidden()
        .sheet(item: $selectedUpcomingEntry) { entry in
            EntryDetailsView(
                entry: entry,
                accountName: accountName(entry.accountID),
                transferAccountName: entry.transferAccountID.map(accountName),
                category: store.category(entry.categoryID),
                isGenerated: !snapshot.entries.contains(where: { $0.id == entry.id }),
                onClose: { selectedUpcomingEntry = nil }
            )
        }
        .onAppear(perform: prepareChartPoints)
        .onChange(of: store.revision) { _, _ in prepareChartPoints() }
        .onChange(of: period) { _, _ in prepareChartPoints() }
        .onChange(of: searchText) { _, _ in prepareUpcomingEntries() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("LIQUIDITÄTSPLAN")
                    .font(Theme.micro)
                    .tracking(1.8)
                    .foregroundStyle(Theme.accent)
                Theme.pageTitle("Was ist heute möglich?")
                Text("Stand \(DateText.string(snapshot.today))").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Label("Live aus deinen Buchungen", systemImage: "arrow.triangle.2.circlepath")
                .font(Theme.micro)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .background(Theme.workspace, in: Capsule())
        }
    }

    private func availableAmountCard(liquidity: LiquidityResult, account: Account) -> some View {
        HeroCard {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        Text("Heute frei verfügbar").font(Theme.body).foregroundStyle(Theme.textSecondary)
                        Text(Money.string(liquidity.availableCents))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(liquidity.availableCents)))
                            .animation(Theme.Motion.value, value: liquidity.availableCents)
                            .foregroundStyle(Theme.accentStrong)
                        if liquidity.shortfallCents > 0 {
                            StatusTag(text: "Unterdeckung \(Money.string(liquidity.shortfallCents))", background: Theme.paleRedBackground, foreground: Theme.paleRedText)
                        }
                    }
                    Spacer(minLength: Theme.Space.sm)
                    IconBadge(systemName: "banknote")
                }

                Divider().overlay(Theme.border)

                HStack(spacing: Theme.Space.xl) {
                    figure(label: "Ist-Saldo", cents: account.currentBalanceCents)
                    Image(systemName: "minus").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                    figure(label: "Bis \(DateText.string(liquidity.horizon)) gebunden", cents: liquidity.requiredCents)
                    Image(systemName: "equal").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                    figure(label: "Frei", cents: liquidity.availableCents, highlighted: true)
                }
            }
        }
    }

    private func figure(label: String, cents: Int, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary).lineLimit(1)
            Text(Money.string(cents))
                .font(Theme.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(highlighted ? Theme.accentStrong : Theme.textPrimary)
        }
    }

    private func weekRingCard(liquidity: LiquidityResult, account: Account) -> some View {
        let available = max(0, account.currentBalanceCents)
        let coverage: Double = liquidity.weekRequiredCents > 0
            ? min(1, Double(available) / Double(liquidity.weekRequiredCents))
            : 1
        let missing = max(0, liquidity.weekRequiredCents - available)
        let hasGap = missing > 0
        let percentText = liquidity.weekRequiredCents > 0
            ? "\(Int((coverage * 100).rounded()))%"
            : "frei"
        return StatCard(icon: "calendar.badge.clock") {
            Text("Bis Sonntag zurückhalten").font(Theme.body).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.md) {
                DonutRing(
                    progress: coverage,
                    centerText: percentText,
                    tint: hasGap ? Theme.chartExpense : Theme.accent,
                    track: hasGap ? Theme.paleRedBackground : Theme.accentSoft
                )
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(Money.string(liquidity.weekRequiredCents)).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("\(Money.string(available)) Kontostand heute")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.textSecondary)
                    if hasGap {
                        Text("\(Money.string(missing)) fehlen")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.paleRedText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .help("Die Reserve umfasst den Mindest-Puffer und den größten erwarteten Rückgang bis Sonntag. Der Ring vergleicht diese Reserve mit dem heutigen Kontostand.")
    }

    private func nextIncomeCard(liquidity: LiquidityResult) -> some View {
        StatCard(icon: "arrow.down.circle") {
            Text("Nächste verlässliche Einnahme").font(Theme.body).foregroundStyle(Theme.textSecondary)
            if let title = liquidity.nextIncomeTitle, let date = liquidity.nextIncomeDate, let cents = liquidity.nextIncomeCents {
                Text(Money.string(cents)).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                Text("\(title) · \(DateText.string(date))").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bis dahin zurückhalten")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.textSecondary)
                    Text(Money.string(liquidity.requiredCents))
                        .font(Theme.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
            } else {
                Text("Keine geplant. Die Vorschau bleibt aktiv.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .help("Dieser Rückhaltebetrag deckt alle bis zur nächsten als verlässlich markierten Einnahme fälligen Ausgaben plus Mindest-Puffer.")
    }

    private var forecastCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Liquiditätsverlauf").font(Theme.sectionHeader)
                        Text("Vergangenheit und Zukunft. Ziehe über das Diagramm, um einen Tag genau zu prüfen.")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button(action: onOpenStatistics) {
                        HStack(spacing: Theme.Space.sm) {
                            Text("Details")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(Theme.accentSoft, in: Circle())
                        }
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(Theme.accentStrong)
                    }
                    .buttonStyle(.plain)
                    .pressable()
                }

                CalendarPeriodBar(period: $period, today: snapshot.today)
                accountFocusBar
                yZoomBar
                forecastMetrics

                if chartPoints.isEmpty {
                    Text("Keine Prognosedaten.").foregroundStyle(Theme.textSecondary)
                } else {
                    Chart {
                        ForEach(chartPoints) { point in
                            LineMark(
                                x: .value("Datum", point.dateValue),
                                y: .value("Saldo", Double(point.balanceCents) / 100)
                            )
                            .foregroundStyle(by: .value("Konto", accountName(point.accountID)))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: lineWidth(point.accountID)))
                            .opacity(lineOpacity(point.accountID))
                        }
                        ForEach(chartMarkers) { point in
                            PointMark(
                                x: .value("Datum", point.dateValue),
                                y: .value("Saldo", Double(point.balanceCents) / 100)
                            )
                            .foregroundStyle(by: .value("Konto", accountName(point.accountID)))
                            .symbolSize(focusedAccountID == nil || focusedAccountID == point.accountID ? 28 : 14)
                            .opacity(lineOpacity(point.accountID))
                        }
                        if let account = primaryAccount {
                            RuleMark(y: .value("Mindest-Puffer", Double(account.minimumBufferCents) / 100))
                                .foregroundStyle(Theme.textSecondary.opacity(0.42))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        if let selectedDate {
                            RuleMark(x: .value("Ausgewähltes Datum", selectedDate))
                                .foregroundStyle(Theme.accent.opacity(0.55))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(domain: chartAccountNames, range: chartAccountColors)
                    .chartXScale(domain: chartXDomain)
                    .chartYScale(domain: chartYDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 8)) { value in
                            AxisGridLine().foregroundStyle(Theme.border.opacity(0.35))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartAxisLabel(date))
                                        .font(Theme.micro)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: chartYTicks) { value in
                            AxisGridLine().foregroundStyle(Theme.border.opacity(0.45))
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount, format: .currency(code: "EUR").precision(.fractionLength(0)))
                                        .font(Theme.micro)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Theme.controlSurface.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(height: 230)
                    .simultaneousGesture(chartMagnificationGesture)
                }
            }
        }
        .onChange(of: period) { _, _ in
            selectedDate = nil
            yZoom = 1
        }
    }

    private var yZoomBar: some View {
        HStack {
            Spacer()
            chartControlGroup(label: "Y-Achse") {
                Button { changeYZoom(by: 1 / 1.35) } label: { Image(systemName: "minus") }
                    .disabled(yZoom <= 1.01)
                Text("\(Int(effectiveYZoom * 100)) %")
                    .font(Theme.micro)
                    .monospacedDigit()
                    .frame(minWidth: 48)
                Button { changeYZoom(by: 1.35) } label: { Image(systemName: "plus") }
                    .disabled(yZoom >= 7.99)
                Button { withAnimation(Theme.Motion.selection) { yZoom = 1 } } label: {
                    Image(systemName: "arrow.up.and.down")
                }
                .help("Y-Achse zurücksetzen")
            }
        }
    }

    private var accountFocusBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.sm) {
                accountFocusButton(id: nil, title: "Alle Konten", color: Theme.textSecondary)
                ForEach(snapshot.accounts) { account in
                    accountFocusButton(id: account.id, title: account.name, color: Color(hex: account.colorHex))
                }
            }
        }
        .financeScrollIndicatorsHidden()
    }

    private func chartControlGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
            content()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accentStrong)
        .padding(.horizontal, Theme.Space.md)
        .frame(height: 36)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func accountFocusButton(id: String?, title: String, color: Color) -> some View {
        let selected = focusedAccountID == id
        return Button {
            withAnimation(Theme.Motion.selection) {
                focusedAccountID = id
                yZoom = 1
                selectedDate = nil
            }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(Theme.micro).lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Theme.textPrimary)
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 32)
            .background(selected ? Theme.accent : Theme.controlSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .pressable()
        .help(selected ? "Alle Linien sichtbar; Skala auf \(title)" : "Skala auf \(title) fokussieren")
    }

    private var forecastMetrics: some View {
        HStack(spacing: 0) {
            if !selectedPoints.isEmpty {
                ForEach(Array(selectedPoints.prefix(4).enumerated()), id: \.element.id) { index, point in
                    chartMetric(label: accountName(point.accountID), cents: point.balanceCents, emphasized: focusedAccountID == point.accountID)
                    if index < min(3, selectedPoints.count - 1) {
                        Divider().frame(height: 34).padding(.horizontal, Theme.Space.md)
                    }
                }
                Spacer()
                Button("Auswahl lösen") { selectedDate = nil }
                    .buttonStyle(.plain)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.accent)
                    .pressable()
            } else {
                chartMetric(label: period.startDate == snapshot.today ? "Heute" : "Start", cents: focusedChartPoints.first?.balanceCents ?? 0)
                metricDivider
                chartMetric(label: "Tiefpunkt", cents: focusedChartPoints.map(\.balanceCents).min() ?? 0)
                metricDivider
                chartMetric(label: "Am Ende", cents: focusedChartPoints.last?.balanceCents ?? 0, emphasized: true)
                Spacer()
                Text(accountName(activeChartAccountID))
                    .font(Theme.micro)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(height: 64)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentTransition(.numericText())
    }

    private var metricDivider: some View {
        Divider().frame(height: 34).padding(.horizontal, Theme.Space.xl)
    }

    private func chartMetric(label: String, cents: Int, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
            Text(Money.string(cents))
                .font(Theme.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(emphasized ? Theme.accentStrong : Theme.textPrimary)
        }
    }

    private var upcomingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Demnächst").font(Theme.sectionHeader)
                    Spacer()
                    FinanceSearchField(text: $searchText, placeholder: "Im Zeitraum suchen")
                    Text(period.label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                }
                if upcomingEntries.isEmpty {
                    Text("Keine Buchungen im ausgewählten Zeitraum.").foregroundStyle(Theme.textSecondary)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(upcomingEntries, id: \.id) { entry in
                            Button {
                                selectedUpcomingEntry = entry
                            } label: {
                                EntryRow(
                                    entry: entry,
                                    accountName: accountName(entry.accountID),
                                    categoryIcon: store.category(entry.categoryID)?.iconName
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pressable()
                            .help("Details zu \(entry.title) anzeigen")
                            if entry.id != upcomingEntries.last?.id { Divider().overlay(Theme.border) }
                        }
                    }
                }
            }
        }
    }

    private func accountName(_ id: String) -> String {
        store.account(id)?.name ?? "Unbekanntes Konto"
    }

    private var markerStride: Int {
        let days = max(1, FinanceCalendar.daysBetween(period.startDate, period.endDate))
        switch days {
        case ..<14: return 1
        case ..<45: return 7
        case ..<200: return 14
        default: return 30
        }
    }

    private var chartAccountIDs: [String] {
        snapshot.accounts.map(\.id)
    }

    private var chartAccountNames: [String] { chartAccountIDs.map(accountName) }
    private var chartAccountColors: [Color] {
        snapshot.accounts.map { Color(hex: $0.colorHex) }
    }

    private var activeChartAccountID: String {
        focusedAccountID ?? primaryAccount?.id ?? chartAccountIDs.first ?? ""
    }

    private var focusedChartPoints: [DashboardChartPoint] {
        chartPointsByAccount[activeChartAccountID] ?? []
    }

    private var selectedPoints: [DashboardChartPoint] {
        guard let selectedDate else { return [] }
        let ids = focusedAccountID.map { [$0] } ?? chartAccountIDs
        return ids.compactMap { id in
            chartPointsByAccount[id]?.min {
                abs($0.dateValue.timeIntervalSince(selectedDate)) < abs($1.dateValue.timeIntervalSince(selectedDate))
            }
        }
    }

    private var effectiveYZoom: Double {
        min(8, max(1, yZoom * Double(liveYMagnification)))
    }

    private var chartYDomain: ClosedRange<Double> {
        let source = focusedAccountID == nil ? chartPoints : focusedChartPoints
        let values = source.map { Double($0.balanceCents) / 100 }
        guard let minimum = values.min(), let maximum = values.max() else { return -100...100 }
        let naturalSpan = max(maximum - minimum, max(abs(maximum), abs(minimum)) * 0.08, 20)
        let paddedSpan = naturalSpan * 1.18
        let visibleSpan = paddedSpan / effectiveYZoom
        let center = (minimum + maximum) / 2
        let rawLower = center - visibleSpan / 2
        let rawUpper = center + visibleSpan / 2
        let lower = minimum >= 0 ? max(0, rawLower) : rawLower
        return lower...max(lower + 1, rawUpper)
    }

    /// Explicit ticks keep Charts from extending an otherwise non-negative
    /// domain below zero while choosing automatic "nice" axis marks.
    private var chartYTicks: [Double] {
        let domain = chartYDomain
        let step = (domain.upperBound - domain.lowerBound) / 5
        guard step.isFinite, step > 0 else { return [domain.lowerBound, domain.upperBound] }
        return (0...5).map { domain.lowerBound + (Double($0) * step) }
    }

    private var periodStart: Date {
        Calendar.current.startOfDay(for: DateText.dateValue(period.startDate))
    }

    private var periodEnd: Date {
        Calendar.current.startOfDay(for: DateText.dateValue(period.endDate))
    }

    private var chartXDomain: ClosedRange<Date> {
        periodStart...max(periodStart, periodEnd)
    }

    private var chartMagnificationGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .updating($liveYMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                yZoom = min(8, max(1, yZoom * Double(value.magnification)))
            }
    }

    private func changeYZoom(by factor: Double) {
        withAnimation(Theme.Motion.selection) {
            yZoom = min(8, max(1, yZoom * factor))
        }
    }

    private func chartAxisLabel(_ date: Date) -> String {
        let days = FinanceCalendar.daysBetween(period.startDate, period.endDate)
        return DateText.chartAxis(date, compact: days > 120)
    }

    private func prepareChartPoints() {
        let points = store.timeline(from: period.startDate, through: period.endDate)
        let prepared: [DashboardChartPoint] = points.compactMap { point in
            guard let date = FinanceCalendar.date(point.date) else { return nil }
            return DashboardChartPoint(date: point.date, dateValue: date, accountID: point.accountID, balanceCents: point.balanceCents)
        }
        let totalDays = max(1, FinanceCalendar.daysBetween(period.startDate, period.endDate) + 1)
        let downsampleStride = max(1, totalDays / 220)
        let displayed = downsampleStride == 1 ? prepared : prepared.filter { point in
            let offset = Calendar.current.dateComponents([.day], from: periodStart, to: point.dateValue).day ?? 0
            return offset % downsampleStride == 0 || point.date == period.endDate
        }
        let markerStep = markerStride
        let markers = displayed.filter { point in
            let day = Calendar.current.dateComponents([.day], from: periodStart, to: point.dateValue).day ?? 0
            return day % markerStep == 0 || point.date == period.endDate
        }
        let grouped: [String: [DashboardChartPoint]] = Dictionary(grouping: displayed) { $0.accountID }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            chartPoints = displayed
            chartMarkers = markers
            chartPointsByAccount = grouped
        }
        prepareUpcomingEntries()
    }

    private func prepareUpcomingEntries() {
        let upcoming = store.occurrencesAndEntries(from: period.startDate, through: period.endDate).filter {
            FinanceSearch.matches(
                $0,
                query: searchText,
                accountName: accountName,
                categoryName: { store.category($0)?.name ?? "" }
            )
        }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            upcomingEntries = upcoming
        }
    }

    private func lineWidth(_ accountID: String) -> CGFloat {
        focusedAccountID == nil || focusedAccountID == accountID ? 2.4 : 1.3
    }

    private func lineOpacity(_ accountID: String) -> Double {
        focusedAccountID == nil || focusedAccountID == accountID ? 1 : 0.25
    }
}

struct EntryRow: View {
    let entry: FinanceEntry
    let accountName: String
    let categoryIcon: String?

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: categoryIcon ?? entryKindIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EntryFormat.amountColor(entry))
                .frame(width: 32, height: 32)
                .background(EntryFormat.amountColor(entry).opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Space.xs / 2) {
                Text(entry.title).font(.system(size: 13, weight: .medium))
                Text("\(accountName) · \(DateText.string(entry.plannedDate))").font(Theme.micro).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(EntryFormat.signedAmount(entry)).font(Theme.bodyEmphasis).monospacedDigit().foregroundStyle(EntryFormat.amountColor(entry))
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private var entryKindIcon: String {
        switch entry.kind {
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        case .transfer: "arrow.left.arrow.right"
        }
    }
}

struct EntryDetailsView: View {
    let entry: FinanceEntry
    let accountName: String
    let transferAccountName: String?
    let category: FinanceCategory?
    let isGenerated: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FinanceModalHeader(
                title: entry.title,
                subtitle: isGenerated ? "Automatisch aus einer Wiederholung erzeugt" : "Details der Buchung",
                systemImage: category?.iconName ?? fallbackIcon,
                onClose: onClose
            )
            Divider().overlay(Theme.border.opacity(0.65))

            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.kind.label).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(EntryFormat.signedAmount(entry))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(EntryFormat.amountColor(entry))
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Theme.Space.md),
                        GridItem(.flexible(), spacing: Theme.Space.md)
                    ],
                    spacing: Theme.Space.md
                ) {
                    detailCell("Datum", value: DateText.string(entry.actualDate ?? entry.plannedDate), icon: "calendar")
                    detailCell("Konto", value: accountName, icon: "wallet.bifold")
                    if let transferAccountName {
                        detailCell("Zielkonto", value: transferAccountName, icon: "arrow.right.circle")
                    }
                    detailCell("Kategorie", value: category?.name ?? "Keine Kategorie", icon: category?.iconName ?? "tag")
                    detailCell("Status", value: isGenerated ? "Vorgemerkt" : entry.status.label, icon: "checkmark.circle")
                }

                if let note = entry.note, !note.isEmpty {
                    detailCell("Notiz", value: note, icon: "note.text")
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xl)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface)
        .onExitCommand(perform: onClose)
    }

    private func detailCell(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentStrong)
                .frame(width: 30, height: 30)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var fallbackIcon: String {
        switch entry.kind {
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        case .transfer: "arrow.left.arrow.right"
        }
    }
}
