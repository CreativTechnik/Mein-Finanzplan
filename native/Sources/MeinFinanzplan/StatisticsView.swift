import SwiftUI
import Charts
import FinanceCore

private struct PeriodTotal: Identifiable, Hashable {
    let start: Date
    let end: Date
    let label: String
    let bookedIncomeCents: Int
    let plannedIncomeCents: Int
    let bookedExpenseCents: Int
    let plannedExpenseCents: Int

    var id: Date { start }
    var incomeCents: Int { bookedIncomeCents + plannedIncomeCents }
    var expenseCents: Int { bookedExpenseCents + plannedExpenseCents }
    var netCents: Int { incomeCents - expenseCents }
}

private struct CategoryTotal: Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String
    let amountCents: Int
}

private struct PeriodAccumulator {
    var bookedIncomeCents = 0
    var plannedIncomeCents = 0
    var bookedExpenseCents = 0
    var plannedExpenseCents = 0
}

struct StatisticsView: View {
    @Environment(AppStore.self) private var store
    @State private var period: CalendarPeriod = CalendarPeriodEngine.period(kind: .halfYear, containing: FinanceCalendar.today())
    @State private var selectedBucketDate: Date?
    @State private var selectedCategory: String?
    @State private var isPresentingReport = false
    @State private var cachedEntries: [FinanceEntry] = []
    @State private var periodTotals: [PeriodTotal] = []
    @State private var expenseByCategory: [CategoryTotal] = []
    @State private var searchText = ""

    private var calendar: Calendar { Calendar.current }
    private var statisticalEntries: [FinanceEntry] { cachedEntries }
    private var periodStartDate: Date { calendar.startOfDay(for: DateText.dateValue(period.startDate)) }
    private var periodEndExclusive: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: DateText.dateValue(period.endDate))) ?? periodStartDate
    }

    private var buckets: [(start: Date, end: Date, label: String)] {
        let start = periodStartDate
        let endExclusive = periodEndExclusive
        switch period.kind {
        case .day:
            return [(start, endExclusive, "Heute")]
        case .week:
            return (0..<7).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                return (date, day(after: date), shortDay(date))
            }
        case .month:
            let dayCount = calendar.dateComponents([.day], from: start, to: endExclusive).day ?? 30
            return (0..<dayCount).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                return (date, day(after: date), dayNumber(date))
            }
        case .quarter:
            return (0..<3).map { offset in
                let bucketStart = calendar.date(byAdding: .month, value: offset, to: start) ?? start
                return (bucketStart, calendar.date(byAdding: .month, value: 1, to: bucketStart) ?? bucketStart, monthName(bucketStart))
            }
        case .halfYear, .year:
            let count = period.kind == .halfYear ? 6 : 12
            return (0..<count).map { offset in
                let bucketStart = calendar.date(byAdding: .month, value: offset, to: start) ?? start
                let bucketEnd = calendar.date(byAdding: .month, value: 1, to: bucketStart) ?? bucketStart
                return (bucketStart, bucketEnd, monthName(bucketStart))
            }
        case .custom:
            return customBuckets(from: start, to: endExclusive)
        }
    }

    /// Custom ranges pick their own granularity so very long spans (years)
    /// still render a readable, performant number of bars: daily up to a
    /// month, weekly up to ~7 months, monthly beyond that.
    private func customBuckets(from start: Date, to endExclusive: Date) -> [(start: Date, end: Date, label: String)] {
        let totalDays = calendar.dateComponents([.day], from: start, to: endExclusive).day ?? 1
        if totalDays <= 31 {
            return (0..<max(1, totalDays)).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                return (date, day(after: date), dayNumber(date))
            }
        } else if totalDays <= 210 {
            var result: [(start: Date, end: Date, label: String)] = []
            var cursor = start
            while cursor < endExclusive {
                let next = min(calendar.date(byAdding: .day, value: 7, to: cursor) ?? endExclusive, endExclusive)
                result.append((cursor, next, shortDate(cursor)))
                cursor = next
            }
            return result
        } else {
            var result: [(start: Date, end: Date, label: String)] = []
            var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
            while cursor < endExclusive {
                let next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? endExclusive
                result.append((max(cursor, start), min(next, endExclusive), monthYearLabel(cursor)))
                cursor = next
            }
            return result
        }
    }

    private func monthYearLabel(_ date: Date) -> String {
        Self.monthYearFormatter.string(from: date)
    }

    private static let monthYearFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "de_DE")
        value.dateFormat = "MMM yy"
        return value
    }()

    private func buildPeriodTotals(from entriesToAggregate: [FinanceEntry]) -> [PeriodTotal] {
        let activeBuckets = buckets
        var accumulators = Array(repeating: PeriodAccumulator(), count: activeBuckets.count)
        let datedEntries = entriesToAggregate
            .map { (date: entryDate($0), entry: $0) }
            .sorted { $0.date < $1.date }
        var bucketIndex = 0

        for item in datedEntries {
            while bucketIndex < activeBuckets.count && item.date >= activeBuckets[bucketIndex].end {
                bucketIndex += 1
            }
            guard bucketIndex < activeBuckets.count,
                  item.date >= activeBuckets[bucketIndex].start,
                  item.entry.status != .cancelled else { continue }

            switch (item.entry.kind, item.entry.status) {
            case (.income, .booked): accumulators[bucketIndex].bookedIncomeCents += item.entry.amountCents
            case (.income, .planned): accumulators[bucketIndex].plannedIncomeCents += item.entry.amountCents
            case (.expense, .booked): accumulators[bucketIndex].bookedExpenseCents += item.entry.amountCents
            case (.expense, .planned): accumulators[bucketIndex].plannedExpenseCents += item.entry.amountCents
            default: break
            }
        }

        return activeBuckets.indices.map { index in
            let bucket = activeBuckets[index]
            let values = accumulators[index]
            return PeriodTotal(
                start: bucket.start,
                end: bucket.end,
                label: bucket.label,
                bookedIncomeCents: values.bookedIncomeCents,
                plannedIncomeCents: values.plannedIncomeCents,
                bookedExpenseCents: values.bookedExpenseCents,
                plannedExpenseCents: values.plannedExpenseCents
            )
        }
    }

    private var activePeriod: PeriodTotal? {
        guard let selectedBucketDate else { return nil }
        return periodTotals.min { abs($0.start.timeIntervalSince(selectedBucketDate)) < abs($1.start.timeIntervalSince(selectedBucketDate)) }
    }

    private var totalIncome: Int { periodTotals.reduce(0) { $0 + $1.incomeCents } }
    private var totalExpense: Int { periodTotals.reduce(0) { $0 + $1.expenseCents } }
    private var totalNet: Int { totalIncome - totalExpense }
    private var activeExpenseTotal: Int { expenseByCategory.reduce(0) { $0 + $1.amountCents } }
    private var xAxisDates: [Date] {
        periodTotals.enumerated().compactMap { index, item in
            let stride = max(1, periodTotals.count / 12)
            return index % stride == 0 || index == periodTotals.count - 1 ? item.start : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                overviewStrip
                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    periodChartCard.frame(maxWidth: .infinity)
                    categoryCard.frame(width: 360)
                }
            }
            .padding(Theme.Space.xxl)
        }
        .financeScrollIndicatorsHidden()
        .onAppear(perform: rebuildStatistics)
        .onChange(of: period) { _, _ in
            selectedBucketDate = nil
            selectedCategory = nil
            rebuildStatistics()
        }
        .onChange(of: selectedBucketDate) { _, _ in
            selectedCategory = nil
            rebuildCategoryTotals(period: activePeriod)
        }
        .onChange(of: store.revision) { _, _ in rebuildStatistics() }
        .onChange(of: searchText) { _, _ in rebuildStatistics() }
        .sheet(isPresented: $isPresentingReport) {
            PDFReportOptionsView(snapshot: store.snapshot) { isPresentingReport = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Theme.pageTitle("Statistik")
                    Text("Vergangenheit und Planung im gewählten Kalenderzeitraum")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                FinanceSearchField(text: $searchText, placeholder: "Zeitraum durchsuchen")
                Button { isPresentingReport = true } label: { Label("PDF-Bericht", systemImage: "doc.richtext") }
                    .buttonStyle(.bordered).controlSize(.large).pressable()
            }
            CalendarPeriodBar(period: $period, today: store.snapshot.today)
        }
    }

    private var overviewStrip: some View {
        Card {
            HStack(spacing: 0) {
                overviewMetric(label: "Einnahmen", cents: totalIncome, color: Theme.chartIncome, icon: "arrow.down.left")
                overviewDivider
                overviewMetric(label: "Ausgaben", cents: totalExpense, color: Theme.chartExpense, icon: "arrow.up.right")
                overviewDivider
                overviewMetric(label: "Differenz", cents: totalNet, color: totalNet >= 0 ? Theme.accentStrong : Theme.chartExpense, icon: "equal")
                Spacer()
                Text(period.label)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.sm)
                    .background(Theme.controlSurface, in: Capsule())
            }
        }
    }

    private func overviewMetric(label: String, cents: Int, color: Color, icon: String) -> some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                Text(Money.string(cents))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
        }
    }

    private var overviewDivider: some View {
        Divider().frame(height: 36).padding(.horizontal, Theme.Space.xl)
    }

    private var periodChartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Verlauf").font(Theme.sectionHeader)
                        Text("Kräftig = gebucht · hell = geplant. Wähle einen Balken für Details.")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: Theme.Space.md) {
                        legendItem("Einnahmen", color: Theme.chartIncome)
                        legendItem("Ausgaben", color: Theme.chartExpense)
                    }
                }

                if periodTotals.allSatisfy({ $0.incomeCents == 0 && $0.expenseCents == 0 }) {
                    emptyState("Noch keine gebuchten oder geplanten Werte in diesem Zeitraum.")
                } else {
                    Chart {
                        ForEach(periodTotals) { item in
                            BarMark(x: .value("Zeitraum", item.start), y: .value("Einnahmen gebucht", Double(item.bookedIncomeCents) / 100))
                                .foregroundStyle(Theme.chartIncome)
                                .position(by: .value("Art", "Einnahmen"))
                                .cornerRadius(4)
                            BarMark(x: .value("Zeitraum", item.start), y: .value("Einnahmen geplant", Double(item.plannedIncomeCents) / 100))
                                .foregroundStyle(Theme.chartIncome.opacity(0.35))
                                .position(by: .value("Art", "Einnahmen"))
                                .cornerRadius(4)
                            BarMark(x: .value("Zeitraum", item.start), y: .value("Ausgaben gebucht", Double(item.bookedExpenseCents) / 100))
                                .foregroundStyle(Theme.chartExpense)
                                .position(by: .value("Art", "Ausgaben"))
                                .cornerRadius(4)
                            BarMark(x: .value("Zeitraum", item.start), y: .value("Ausgaben geplant", Double(item.plannedExpenseCents) / 100))
                                .foregroundStyle(Theme.chartExpense.opacity(0.35))
                                .position(by: .value("Art", "Ausgaben"))
                                .cornerRadius(4)
                        }
                        if let selectedBucketDate {
                            RuleMark(x: .value("Ausgewählter Zeitraum", selectedBucketDate))
                                .foregroundStyle(Theme.accent.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartLegend(.hidden)
                    .id(chartIdentity)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onEnded { value in
                                            selectBucket(at: value.location, proxy: proxy, geometry: geometry)
                                        }
                                )
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: xAxisDates) { value in
                            AxisGridLine().foregroundStyle(Theme.border.opacity(0.35))
                            AxisValueLabel {
                                if let date = value.as(Date.self), let item = periodTotals.first(where: { calendar.isDate($0.start, inSameDayAs: date) }) {
                                    Text(item.label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea.background(Theme.controlSurface.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private var categoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Ausgaben nach Kategorie").font(Theme.sectionHeader)
                        Text(activePeriod?.label ?? "Gesamter Zeitraum · \(period.label)").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if selectedBucketDate != nil {
                        Button("Gesamter Zeitraum") { selectedBucketDate = nil }
                            .buttonStyle(.plain).font(Theme.micro).foregroundStyle(Theme.accent).pressable()
                    }
                }

                if expenseByCategory.isEmpty {
                    emptyState("Keine gebuchten oder geplanten Ausgaben in diesem Abschnitt.")
                } else {
                    HStack(alignment: .center, spacing: Theme.Space.lg) {
                        ZStack {
                            Chart(Array(expenseByCategory.enumerated()), id: \.element.id) { index, item in
                                SectorMark(angle: .value("Betrag", item.amountCents), innerRadius: .ratio(0.68), angularInset: 2)
                                    .cornerRadius(3)
                                    .foregroundStyle(categoryColor(index))
                                    .opacity(selectedCategory == nil || selectedCategory == item.id ? 1 : 0.24)
                            }
                            .chartLegend(.hidden)
                            VStack(spacing: 2) {
                                Text("Gesamt").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                                Text(Money.string(activeExpenseTotal)).font(Theme.bodyEmphasis).monospacedDigit()
                            }
                        }
                        .frame(width: 142, height: 142)

                        VStack(spacing: Theme.Space.sm) {
                            ForEach(Array(expenseByCategory.prefix(6).enumerated()), id: \.element.id) { index, item in
                                Button {
                                    withAnimation(Theme.Motion.selection) { selectedCategory = selectedCategory == item.id ? nil : item.id }
                                } label: {
                                    HStack(spacing: Theme.Space.sm) {
                                        Image(systemName: item.iconName).font(.system(size: 10, weight: .semibold)).foregroundStyle(categoryColor(index)).frame(width: 14)
                                        Text(item.name).font(Theme.micro).lineLimit(1)
                                        Spacer()
                                        Text(percentText(item.amountCents)).font(Theme.micro).monospacedDigit().foregroundStyle(Theme.textSecondary)
                                    }
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, Theme.Space.sm)
                                    .frame(height: 28)
                                    .background(selectedCategory == item.id ? Theme.controlHover : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .pressable()
                            }
                        }
                    }

                    if let selected = expenseByCategory.first(where: { $0.id == selectedCategory }) {
                        HStack {
                            Label(selected.name, systemImage: selected.iconName).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(Money.string(selected.amountCents)).font(Theme.bodyEmphasis).monospacedDigit()
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 38)
                        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private func entryDate(_ entry: FinanceEntry) -> Date {
        calendar.startOfDay(for: DateText.dateValue(entry.actualDate ?? entry.plannedDate))
    }

    private func day(after date: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: date) ?? date }

    private func shortDay(_ date: Date) -> String { DateText.shortDay(date) }
    private func dayNumber(_ date: Date) -> String { DateText.dayNumber(date) }
    private func shortDate(_ date: Date) -> String { DateText.shortDate(date) }
    private func monthName(_ date: Date) -> String { DateText.shortMonth(date) }

    private func rebuildStatistics() {
        let merged = store.occurrencesAndEntries(from: period.startDate, through: period.endDate).filter {
            FinanceSearch.matches(
                $0,
                query: searchText,
                accountName: { store.account($0)?.name ?? "" },
                categoryName: { store.category($0)?.name ?? "" }
            )
        }
        let totals = buildPeriodTotals(from: merged)
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            cachedEntries = merged
            periodTotals = totals
        }
        rebuildCategoryTotals(entries: merged, period: selectedPeriod(in: totals))
    }

    private var chartIdentity: String {
        "\(period.kind.rawValue):\(period.startDate):\(period.endDate)"
    }

    private func selectBucket(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame.map({ geometry[$0] }), frame.contains(location) else { return }
        let relativeX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: relativeX),
              let nearest = periodTotals.min(by: {
                  abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
              }) else { return }
        selectedBucketDate = nearest.start
    }

    private func rebuildCategoryTotals(entries: [FinanceEntry]? = nil, period selectedPeriod: PeriodTotal? = nil) {
        let source = entries ?? statisticalEntries
        var totalsByCategory: [String: Int] = [:]
        for entry in source where entry.kind == .expense && entry.status != .cancelled {
            let date = entryDate(entry)
            if let selectedPeriod {
                guard date >= selectedPeriod.start && date < selectedPeriod.end else { continue }
            } else {
                guard date >= periodStartDate && date < periodEndExclusive else { continue }
            }
            totalsByCategory[entry.categoryID ?? "", default: 0] += entry.amountCents
        }
        expenseByCategory = totalsByCategory.map { categoryID, cents in
            let category = store.category(categoryID.isEmpty ? nil : categoryID)
            return CategoryTotal(
                id: categoryID.isEmpty ? "uncategorized" : categoryID,
                name: category?.name ?? "Ohne Kategorie",
                iconName: category?.iconName ?? "tag",
                amountCents: cents
            )
        }
        .sorted { $0.amountCents > $1.amountCents }
    }

    private func selectedPeriod(in totals: [PeriodTotal]) -> PeriodTotal? {
        guard let selectedBucketDate else { return nil }
        return totals.min {
            abs($0.start.timeIntervalSince(selectedBucketDate)) < abs($1.start.timeIntervalSince(selectedBucketDate))
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(Theme.micro).foregroundStyle(Theme.textSecondary)
        }
    }

    private func emptyState(_ message: String) -> some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "chart.bar.xaxis").foregroundStyle(Theme.textSecondary)
            Text(message).font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 142)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func percentText(_ cents: Int) -> String {
        guard activeExpenseTotal > 0 else { return "0 %" }
        return "\(Int((Double(cents) / Double(activeExpenseTotal) * 100).rounded())) %"
    }

    private func categoryColor(_ index: Int) -> Color {
        let colors: [Color] = [Theme.accent, Theme.chartExpense, Theme.chartIncome, Theme.mist, Theme.paleYellowText, Theme.chartTransfer]
        return colors[index % colors.count]
    }
}
