import SwiftUI
import FinanceCore

/// Month-at-a-glance view for both materialized bookings and generated
/// recurrence occurrences. Data is prepared only when the month or store
/// revision changes, keeping scrolling and selection independent from SQLite.
struct CalendarView: View {
    @Environment(AppStore.self) private var store
    @State private var month = CalendarPeriodEngine.period(kind: .month, containing: FinanceCalendar.today())
    @State private var selectedDay = FinanceCalendar.today()
    @State private var entriesByDay: [String: [FinanceEntry]] = [:]
    @State private var monthEntries: [FinanceEntry] = []
    @State private var materializedEntryIDs: Set<String> = []
    @State private var selectedEntry: FinanceEntry?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.sm), count: 7)
    private let weekdaySymbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                summaryStrip
                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    calendarCard.frame(maxWidth: .infinity)
                    selectedDayCard.frame(width: 330)
                }
            }
            .padding(Theme.Space.xxl)
        }
        .financeScrollIndicatorsHidden()
        .onAppear(perform: rebuildCalendar)
        .onChange(of: month) { _, _ in
            if selectedDay < month.startDate || selectedDay > month.endDate {
                selectedDay = month.startDate
            }
            rebuildCalendar()
        }
        .onChange(of: store.revision) { _, _ in rebuildCalendar() }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailsView(
                entry: entry,
                accountName: accountName(entry.accountID),
                transferAccountName: entry.transferAccountID.map(accountName),
                category: store.category(entry.categoryID),
                isGenerated: !materializedEntryIDs.contains(entry.id),
                onClose: { selectedEntry = nil }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("FINANZKALENDER")
                    .font(Theme.micro)
                    .tracking(1.8)
                    .foregroundStyle(Theme.accent)
                Theme.pageTitle("Wann bewegt sich dein Geld?")
                Text("Gebuchte und vorgemerkte Ein-, Aus- und Umbuchungen an ihrem jeweiligen Tag.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            CalendarPeriodBar(period: $month, today: store.snapshot.today, kinds: [.month])
        }
    }

    private var summaryStrip: some View {
        Card {
            HStack(spacing: 0) {
                summaryMetric("Einnahmen", cents: total(for: .income), color: Theme.chartIncome, icon: "arrow.down.left")
                summaryDivider
                summaryMetric("Ausgaben", cents: total(for: .expense), color: Theme.chartExpense, icon: "arrow.up.right")
                summaryDivider
                summaryMetric("Termine", value: "\(monthEntries.count)", color: Theme.accentStrong, icon: "calendar.badge.clock")
                Spacer()
                legend("Einnahme", color: Theme.chartIncome)
                legend("Ausgabe", color: Theme.chartExpense)
                legend("Umbuchung", color: Theme.chartTransfer)
            }
        }
    }

    private var summaryDivider: some View {
        Divider().frame(height: 34).padding(.horizontal, Theme.Space.xl)
    }

    private func summaryMetric(_ label: String, cents: Int, color: Color, icon: String) -> some View {
        summaryMetric(label, value: Money.string(cents), color: color, icon: icon)
    }

    private func summaryMetric(_ label: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                Text(value).font(Theme.bodyEmphasis).monospacedDigit().foregroundStyle(color)
            }
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(Theme.micro).foregroundStyle(Theme.textSecondary)
        }
        .padding(.leading, Theme.Space.md)
    }

    private var calendarCard: some View {
        let days = gridDays
        return Card {
            VStack(spacing: Theme.Space.sm) {
                LazyVGrid(columns: columns, spacing: Theme.Space.sm) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol.uppercased())
                            .font(Theme.micro)
                            .tracking(1.2)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                    ForEach(days.indices, id: \.self) { index in
                        if let day = days[index] {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 94)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ isoDay: String) -> some View {
        let entries = entriesByDay[isoDay] ?? []
        let isSelected = isoDay == selectedDay
        let isToday = isoDay == store.snapshot.today
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(dayNumber(isoDay))
                    .font(Theme.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : isSelected ? Theme.accentStrong : Theme.textPrimary)
                    .frame(width: 25, height: 25)
                    .background(isToday ? Theme.accent : Color.clear, in: Circle())
                Spacer()
                if !entries.isEmpty {
                    Text("\(entries.count)")
                        .font(Theme.micro)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            ForEach(Array(entries.prefix(2))) { entry in
                Button { selectedEntry = entry } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Circle().fill(color(for: entry.kind)).frame(width: 6, height: 6)
                        Text(entry.title).font(Theme.micro).lineLimit(1)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.xs)
                    .frame(maxWidth: .infinity, minHeight: 21, alignment: .leading)
                    .background(color(for: entry.kind).opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("\(entry.title): \(EntryFormat.signedAmount(entry))")
            }

            if entries.count > 2 {
                Text("+ \(entries.count - 2) weitere")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, Theme.Space.xs)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading)
        .background(isSelected ? Theme.accentSoft : Theme.controlSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.7) : Theme.border.opacity(0.45), lineWidth: isSelected ? 1.2 : 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selectedDay = isoDay }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(DateText.string(isoDay)), \(entries.count) Buchungen")
    }

    private var selectedDayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("AUSGEWÄHLTER TAG")
                        .font(Theme.micro)
                        .tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    Text(DateText.string(selectedDay)).font(Theme.sectionHeader)
                    Text(dayBalanceText)
                        .font(Theme.micro)
                        .foregroundStyle(Theme.textSecondary)
                }

                Divider().overlay(Theme.border)

                if selectedDayEntries.isEmpty {
                    VStack(spacing: Theme.Space.md) {
                        Image(systemName: "calendar.badge.minus")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Theme.textSecondary)
                        Text("An diesem Tag ist nichts vorgemerkt.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 190)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(selectedDayEntries) { entry in
                            Button { selectedEntry = entry } label: {
                                EntryRow(
                                    entry: entry,
                                    accountName: accountName(entry.accountID),
                                    categoryIcon: store.category(entry.categoryID)?.iconName
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Buchungsdetails öffnen")
                            if entry.id != selectedDayEntries.last?.id {
                                Divider().overlay(Theme.border)
                            }
                        }
                    }
                }
            }
        }
    }

    private var gridDays: [String?] {
        let firstDate = DateText.dateValue(month.startDate)
        let weekday = calendar.component(.weekday, from: firstDate)
        let leadingEmptyDays = (weekday + 5) % 7
        let numberOfDays = FinanceCalendar.daysBetween(month.startDate, month.endDate) + 1
        var result = Array<String?>(repeating: nil, count: leadingEmptyDays)
        result.append(contentsOf: (0..<numberOfDays).map { FinanceCalendar.addingDays($0, to: month.startDate) })
        let trailingEmptyDays = (7 - result.count % 7) % 7
        result.append(contentsOf: Array<String?>(repeating: nil, count: trailingEmptyDays))
        return result
    }

    private var selectedDayEntries: [FinanceEntry] {
        entriesByDay[selectedDay] ?? []
    }

    private var dayBalanceText: String {
        let income = selectedDayEntries.lazy.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
        let expense = selectedDayEntries.lazy.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
        if income == 0 && expense == 0 { return "Keine Kontobewegung" }
        return "+ \(Money.string(income)) · − \(Money.string(expense))"
    }

    private func total(for kind: EntryKind) -> Int {
        monthEntries.lazy.filter { $0.kind == kind }.reduce(0) { $0 + $1.amountCents }
    }

    private func dayNumber(_ isoDay: String) -> String {
        String(Int(isoDay.suffix(2)) ?? 0)
    }

    private func accountName(_ id: String) -> String {
        store.account(id)?.name ?? "Unbekanntes Konto"
    }

    private func color(for kind: EntryKind) -> Color {
        switch kind {
        case .income: Theme.chartIncome
        case .expense: Theme.chartExpense
        case .transfer: Theme.chartTransfer
        }
    }

    private func rebuildCalendar() {
        let entries = store.occurrencesAndEntries(from: month.startDate, through: month.endDate)
        var grouped: [String: [FinanceEntry]] = [:]
        grouped.reserveCapacity(min(entries.count, 31))
        for entry in entries {
            grouped[entry.actualDate ?? entry.plannedDate, default: []].append(entry)
        }
        let materializedIDs = Set(store.snapshot.entries.lazy.map(\.id))
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            monthEntries = entries
            entriesByDay = grouped
            materializedEntryIDs = materializedIDs
        }
    }
}
