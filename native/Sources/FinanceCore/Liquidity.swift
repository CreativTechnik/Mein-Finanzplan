import Foundation

public enum FinanceCalendar {
    public static let timeZone = TimeZone(identifier: "Europe/Berlin")!

    public static func today(now: Date = Date()) -> String {
        formatter.string(from: now)
    }

    public static func date(_ value: String) -> Date? {
        formatter.date(from: value)
    }

    public static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }

    public static func addingDays(_ days: Int, to value: String) -> String {
        guard let date = date(value), let result = calendar.date(byAdding: .day, value: days, to: date) else { return value }
        return string(result)
    }

    public static func addingMonths(_ months: Int, to value: String, anchorDay: Int? = nil) -> String {
        guard let source = date(value) else { return value }
        let day = anchorDay ?? calendar.component(.day, from: source)
        guard let moved = calendar.date(byAdding: .month, value: months, to: source) else { return value }
        var components = calendar.dateComponents([.year, .month], from: moved)
        let range = calendar.range(of: .day, in: .month, for: moved) ?? 1..<29
        components.day = min(day, range.count)
        return calendar.date(from: components).map(string) ?? string(moved)
    }

    public static func addingYears(_ years: Int, to value: String, anchorDay: Int? = nil) -> String {
        addingMonths(years * 12, to: value, anchorDay: anchorDay)
    }

    public static func endOfWeek(containing value: String) -> String {
        guard let source = date(value) else { return value }
        let weekday = calendar.component(.weekday, from: source)
        let days = weekday == 1 ? 0 : 8 - weekday
        return addingDays(days, to: value)
    }

    public static func startOfWeek(containing value: String) -> String {
        let daysSinceMonday = (weekday(of: value) + 5) % 7
        return addingDays(-daysSinceMonday, to: value)
    }

    /// `Calendar`'s numbering: 1 = Sunday ... 7 = Saturday.
    public static func weekday(of value: String) -> Int {
        guard let source = date(value) else { return 1 }
        return calendar.component(.weekday, from: source)
    }

    public static func day(of value: String) -> Int {
        guard let source = date(value) else { return 1 }
        return calendar.component(.day, from: source)
    }

    public static func yearMonth(_ value: String) -> (year: Int, month: Int) {
        guard let source = date(value) else { return (2000, 1) }
        let components = calendar.dateComponents([.year, .month], from: source)
        return (components.year ?? 2000, components.month ?? 1)
    }

    public static func daysInMonth(containing value: String) -> Int {
        guard let source = date(value) else { return 30 }
        return calendar.range(of: .day, in: .month, for: source)?.count ?? 30
    }

    public static func startOfMonth(containing value: String) -> String {
        guard let source = date(value) else { return value }
        var components = calendar.dateComponents([.year, .month], from: source)
        components.day = 1
        return calendar.date(from: components).map(string) ?? value
    }

    public static func endOfMonth(containing value: String) -> String {
        let start = startOfMonth(containing: value)
        return addingDays(daysInMonth(containing: start) - 1, to: start)
    }

    public static func startOfQuarter(containing value: String) -> String {
        let (year, month) = yearMonth(value)
        let quarterStartMonth = (month - 1) / 3 * 3 + 1
        return dateString(year: year, month: quarterStartMonth, day: 1)
    }

    public static func endOfQuarter(containing value: String) -> String {
        let start = startOfQuarter(containing: value)
        let lastMonthStart = addingMonths(2, to: start, anchorDay: 1)
        return endOfMonth(containing: lastMonthStart)
    }

    public static func startOfHalfYear(containing value: String) -> String {
        let (year, month) = yearMonth(value)
        return dateString(year: year, month: month <= 6 ? 1 : 7, day: 1)
    }

    public static func endOfHalfYear(containing value: String) -> String {
        let start = startOfHalfYear(containing: value)
        let lastMonthStart = addingMonths(5, to: start, anchorDay: 1)
        return endOfMonth(containing: lastMonthStart)
    }

    public static func startOfYear(containing value: String) -> String {
        let (year, _) = yearMonth(value)
        return dateString(year: year, month: 1, day: 1)
    }

    public static func endOfYear(containing value: String) -> String {
        let (year, _) = yearMonth(value)
        return dateString(year: year, month: 12, day: 31)
    }

    /// Returns a valid ISO date in the month starting at `monthStart`, clamping
    /// `day` to that month's last day.
    public static func dateString(monthStart: String, day: Int) -> String {
        let (year, month) = yearMonth(monthStart)
        let clamped = min(max(1, day), daysInMonth(containing: monthStart))
        return dateString(year: year, month: month, day: clamped)
    }

    public static func dateString(year: Int, month: Int, day: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components).map(string) ?? String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The latest date on or before `deadline` whose weekday matches `weekday`
    /// (`Calendar` numbering: 1 = Sunday ... 7 = Saturday).
    public static func lastWeekday(_ weekday: Int, onOrBefore deadline: String) -> String {
        var current = deadline
        var guardCount = 0
        while FinanceCalendar.weekday(of: current) != weekday, guardCount < 7 {
            current = addingDays(-1, to: current)
            guardCount += 1
        }
        return current
    }

    /// Inclusive number of days between two ISO dates (`to` - `from`).
    public static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let start = date(from), let end = date(to) else { return 0 }
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        value.locale = Locale(identifier: "de_DE")
        return value
    }()

    private static let formatter: DateFormatter = {
        let value = DateFormatter()
        value.calendar = calendar
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = timeZone
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()
}

private struct Movement: Sendable {
    let entry: FinanceEntry
    let accountID: String
    let date: String
    let deltaCents: Int
}

public enum FinanceEngine {
    public static func occurrences(for rule: RecurringRule, from: String, through: String) -> [FinanceEntry] {
        guard rule.isActive, rule.startDate <= through, rule.endDate.map({ $0 >= from }) ?? true else { return [] }
        let excluded = Set(rule.excludedDates)
        var result: [FinanceEntry] = []
        var guardCount = 0

        if case .exactDates(let dates) = rule.schedule {
            return Set(dates)
                .filter { date in
                    date >= from && date <= through && date >= rule.startDate
                        && (rule.endDate.map { date <= $0 } ?? true)
                        && !excluded.contains(date)
                }
                .sorted()
                .map { makeOccurrence(rule: rule, date: $0) }
        }

        if rule.frequency == .monthly {
            let legacyAnchor = Int(rule.startDate.suffix(2))
            var monthCursor = FinanceCalendar.startOfMonth(containing: rule.startDate)
            while guardCount < 10_000 {
                guardCount += 1
                if let end = rule.endDate, monthCursor > end { break }
                let due = dueDate(inMonth: monthCursor, schedule: rule.schedule, kind: rule.kind, legacyAnchor: legacyAnchor, excluded: excluded)
                if due > through { break }
                if due >= from, due >= rule.startDate, rule.endDate.map({ due <= $0 }) ?? true {
                    result.append(makeOccurrence(rule: rule, date: due))
                }
                monthCursor = FinanceCalendar.addingMonths(max(1, rule.interval), to: monthCursor, anchorDay: 1)
            }
            return result
        }

        var current = rule.startDate
        let anchor = rule.dueDay ?? Int(rule.startDate.suffix(2))
        while current < from, guardCount < 10_000 {
            current = advance(current, rule: rule, anchorDay: anchor)
            guardCount += 1
        }
        while current <= through, guardCount < 10_000 {
            if rule.endDate.map({ current <= $0 }) ?? true {
                result.append(makeOccurrence(rule: rule, date: current))
            }
            current = advance(current, rule: rule, anchorDay: anchor)
            guardCount += 1
        }
        return result
    }

    private static func makeOccurrence(rule: RecurringRule, date: String) -> FinanceEntry {
        FinanceEntry(
            id: "occ:\(rule.id):\(date)",
            title: rule.title,
            amountCents: rule.amountCents(on: date),
            kind: rule.kind,
            accountID: rule.accountID,
            transferAccountID: rule.transferAccountID,
            categoryID: rule.categoryID,
            recurrenceID: rule.id,
            plannedDate: date,
            status: .planned,
            note: "Automatisch aus Wiederholung",
            isReliable: rule.isReliable
        )
    }

    /// Resolves the due date within the month starting at `monthStart`, then
    /// rolls back to the previous eligible day if the manual exclusion list
    /// catches it. For `weekdayBeforeDeadline`, the rollback moves a full week
    /// at a time so the weekday is preserved, matching a "use the previous
    /// valid Wednesday" style holiday exception.
    private static func dueDate(inMonth monthStart: String, schedule: RecurrenceSchedule, kind: EntryKind, legacyAnchor: Int?, excluded: Set<String>) -> String {
        switch schedule {
        case .fixedDay(let day):
            let target = FinanceCalendar.dateString(monthStart: monthStart, day: day ?? legacyAnchor ?? 1)
            return rollBackDaily(target, excluded: excluded)
        case .dateWindow(let startDay, let endDay):
            let day = kind == .income ? endDay : startDay
            let target = FinanceCalendar.dateString(monthStart: monthStart, day: day)
            return rollBackDaily(target, excluded: excluded)
        case .weekdayBeforeDeadline(let weekday, let deadlineDay):
            let deadline = FinanceCalendar.dateString(monthStart: monthStart, day: deadlineDay)
            let target = FinanceCalendar.lastWeekday(weekday, onOrBefore: deadline)
            return rollBackWeekly(target, excluded: excluded)
        case .exactDates:
            return monthStart
        }
    }

    private static func rollBackDaily(_ date: String, excluded: Set<String>) -> String {
        var current = date
        var guardCount = 0
        while excluded.contains(current), guardCount < 31 {
            current = FinanceCalendar.addingDays(-1, to: current)
            guardCount += 1
        }
        return current
    }

    private static func rollBackWeekly(_ date: String, excluded: Set<String>) -> String {
        var current = date
        var guardCount = 0
        while excluded.contains(current), guardCount < 12 {
            current = FinanceCalendar.addingDays(-7, to: current)
            guardCount += 1
        }
        return current
    }

    /// Every materialized entry, plus generated future occurrences not yet
    /// materialized, within `[start, end]`. Past dates never receive synthetic
    /// occurrences - only entries that actually exist.
    public static func occurrencesAndEntries(entries: [FinanceEntry], rules: [RecurringRule], today: String, start: String, end: String) -> [FinanceEntry] {
        guard start <= end else { return [] }
        let materialized = Set(entries.compactMap { entry -> String? in
            guard let recurrenceID = entry.recurrenceID else { return nil }
            return "\(recurrenceID):\(entry.plannedDate)"
        })
        let generationStart = max(start, today)
        let generated: [FinanceEntry] = generationStart <= end
            ? rules.flatMap { occurrences(for: $0, from: generationStart, through: end) }
                .filter { !materialized.contains("\($0.recurrenceID ?? ""):\($0.plannedDate)") }
            : []
        let matched = entries.filter {
            $0.status != .cancelled && ($0.actualDate ?? $0.plannedDate) >= start && ($0.actualDate ?? $0.plannedDate) <= end
        }
        return (matched + generated).sorted {
            let leftDate = $0.actualDate ?? $0.plannedDate
            let rightDate = $1.actualDate ?? $1.plannedDate
            if leftDate != rightDate { return leftDate < rightDate }
            return $0.title < $1.title
        }
    }

    public static func snapshot(accounts: [Account], entries: [FinanceEntry], rules: [RecurringRule], today: String, days: Int = 90) -> (occurrences: [FinanceEntry], liquidity: LiquidityResult?, forecast: [ForecastPoint]) {
        let end = FinanceCalendar.addingDays(days, to: today)
        let materialized = Set(entries.compactMap { entry -> String? in
            guard let recurrenceID = entry.recurrenceID else { return nil }
            return "\(recurrenceID):\(entry.plannedDate)"
        })
        let generatedOccurrences = rules.flatMap { occurrences(for: $0, from: today, through: end) }
            .filter { !materialized.contains("\($0.recurrenceID ?? ""):\($0.plannedDate)") }
        let future = entries.filter { $0.status != .cancelled && ($0.actualDate ?? $0.plannedDate) >= today && ($0.actualDate ?? $0.plannedDate) <= end }
        let ledger = movements(from: future + generatedOccurrences)
        let primary = accounts.first(where: \ .isPrimary) ?? accounts.first
        let liquidity = primary.map { calculateLiquidity(account: $0, movements: ledger, today: today, fallbackEnd: end) }
        let forecast = buildForecast(accounts: accounts, movements: ledger, today: today, days: days)
        return (generatedOccurrences, liquidity, forecast)
    }

    /// Account balances across an arbitrary calendar range, including dates
    /// before today. History is derived only from entries that actually exist
    /// (booked, balance-affecting movements already baked into
    /// `currentBalanceCents`) - never fabricated. The future portion mirrors
    /// `snapshot`'s forward projection (booked and planned entries, plus
    /// generated occurrences).
    public static func timeline(accounts: [Account], entries: [FinanceEntry], rules: [RecurringRule], today: String, start: String, end: String) -> [ForecastPoint] {
        guard start <= end else { return [] }
        let materialized = Set(entries.compactMap { entry -> String? in
            guard let recurrenceID = entry.recurrenceID else { return nil }
            return "\(recurrenceID):\(entry.plannedDate)"
        })
        let generationStart = max(start, today)
        let futureOccurrences: [FinanceEntry] = generationStart <= end
            ? rules.flatMap { occurrences(for: $0, from: generationStart, through: end) }
                .filter { !materialized.contains("\($0.recurrenceID ?? ""):\($0.plannedDate)") }
            : []
        let forwardMovements = movements(from: entries.filter { $0.status != .cancelled } + futureOccurrences)
            .filter { $0.date > today && $0.date <= end }
        let backwardMovements = movements(from: entries.filter { $0.status == .booked && $0.affectsBalance })
            .filter { $0.date <= today && $0.date > start }

        var balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.currentBalanceCents) })
        // The legacy persistence layer applies every booked entry immediately,
        // including entries dated in the future. Rewind those effects for the
        // chart's true "today" anchor; forwardMovements then applies each one
        // exactly once on its actual date.
        let futureAlreadyApplied = movements(from: entries.filter { $0.status == .booked && $0.affectsBalance })
            .filter { $0.date > today }
        for movement in futureAlreadyApplied {
            balances[movement.accountID, default: 0] -= movement.deltaCents
        }
        var result: [ForecastPoint] = []

        if start < today {
            var histBalances = balances
            var pointer = backwardMovements.count - 1
            var histPoints: [ForecastPoint] = []
            var day = FinanceCalendar.addingDays(-1, to: today)
            while day >= start {
                let boundary = FinanceCalendar.addingDays(1, to: day)
                while pointer >= 0, backwardMovements[pointer].date == boundary {
                    histBalances[backwardMovements[pointer].accountID, default: 0] -= backwardMovements[pointer].deltaCents
                    pointer -= 1
                }
                histPoints.append(contentsOf: accounts.map { ForecastPoint(date: day, accountID: $0.id, balanceCents: histBalances[$0.id, default: 0]) })
                day = FinanceCalendar.addingDays(-1, to: day)
            }
            result.append(contentsOf: histPoints.reversed())
        }

        if today >= start && today <= end {
            result.append(contentsOf: accounts.map { ForecastPoint(date: today, accountID: $0.id, balanceCents: balances[$0.id, default: 0]) })
        }

        if end > today {
            var movementIndex = 0
            var day = FinanceCalendar.addingDays(1, to: today)
            while day <= end {
                while movementIndex < forwardMovements.count, forwardMovements[movementIndex].date < day { movementIndex += 1 }
                while movementIndex < forwardMovements.count, forwardMovements[movementIndex].date == day {
                    balances[forwardMovements[movementIndex].accountID, default: 0] += forwardMovements[movementIndex].deltaCents
                    movementIndex += 1
                }
                result.append(contentsOf: accounts.map { ForecastPoint(date: day, accountID: $0.id, balanceCents: balances[$0.id, default: 0]) })
                day = FinanceCalendar.addingDays(1, to: day)
            }
        }

        return result
    }

    private static func advance(_ value: String, rule: RecurringRule, anchorDay: Int?) -> String {
        let interval = max(1, rule.interval)
        return switch rule.frequency {
        case .monthly: FinanceCalendar.addingMonths(interval, to: value, anchorDay: anchorDay)
        case .weekly: FinanceCalendar.addingDays(interval * 7, to: value)
        case .yearly: FinanceCalendar.addingYears(interval, to: value, anchorDay: anchorDay)
        }
    }

    private static func movements(from entries: [FinanceEntry]) -> [Movement] {
        entries.flatMap { entry -> [Movement] in
            let date = entry.actualDate ?? entry.plannedDate
            return switch entry.kind {
            case .income:
                [Movement(entry: entry, accountID: entry.accountID, date: date, deltaCents: entry.amountCents)]
            case .expense:
                [Movement(entry: entry, accountID: entry.accountID, date: date, deltaCents: -entry.amountCents)]
            case .transfer:
                [
                    Movement(entry: entry, accountID: entry.accountID, date: date, deltaCents: -entry.amountCents),
                    Movement(entry: entry, accountID: entry.transferAccountID ?? "", date: date, deltaCents: entry.amountCents)
                ]
            }
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if ($0.deltaCents < 0) != ($1.deltaCents < 0) { return $0.deltaCents < 0 }
            return $0.entry.title < $1.entry.title
        }
    }

    private static func requirement(account: Account, movements: [Movement], today: String, through horizon: String, excludingIncomeID: String? = nil) -> (required: Int, available: Int, shortfall: Int, risk: String?) {
        var projected = account.currentBalanceCents
        var minimum = projected
        var firstRisk = projected < account.minimumBufferCents ? today : nil
        for movement in movements where movement.accountID == account.id && movement.date >= today && movement.date <= horizon {
            if movement.entry.id == excludingIncomeID, movement.deltaCents > 0 { continue }
            projected += movement.deltaCents
            minimum = min(minimum, projected)
            if firstRisk == nil, projected < account.minimumBufferCents { firstRisk = movement.date }
        }
        let drawdown = max(0, account.currentBalanceCents - minimum)
        let required = account.minimumBufferCents + drawdown
        return (required, max(0, account.currentBalanceCents - required), max(0, required - account.currentBalanceCents), firstRisk)
    }

    private static func calculateLiquidity(account: Account, movements: [Movement], today: String, fallbackEnd: String) -> LiquidityResult {
        let income = movements.first { $0.accountID == account.id && $0.date >= today && $0.deltaCents > 0 && $0.entry.isReliable }
        let horizon = income?.date ?? fallbackEnd
        let period = requirement(account: account, movements: movements, today: today, through: horizon, excludingIncomeID: income?.entry.id)
        let week = requirement(account: account, movements: movements, today: today, through: FinanceCalendar.endOfWeek(containing: today))
        return LiquidityResult(
            horizon: horizon,
            availableCents: period.available,
            requiredCents: period.required,
            shortfallCents: period.shortfall,
            weekRequiredCents: week.required,
            nextIncomeTitle: income?.entry.title,
            nextIncomeDate: income?.date,
            nextIncomeCents: income?.deltaCents,
            firstRiskDate: period.risk
        )
    }

    private static func buildForecast(accounts: [Account], movements: [Movement], today: String, days: Int) -> [ForecastPoint] {
        var balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.currentBalanceCents) })
        var result: [ForecastPoint] = []
        var movementIndex = 0
        for offset in 0...days {
            let date = FinanceCalendar.addingDays(offset, to: today)
            while movementIndex < movements.count, movements[movementIndex].date < date { movementIndex += 1 }
            while movementIndex < movements.count, movements[movementIndex].date == date {
                let movement = movements[movementIndex]
                balances[movement.accountID, default: 0] += movement.deltaCents
                movementIndex += 1
            }
            result.append(contentsOf: accounts.map { ForecastPoint(date: date, accountID: $0.id, balanceCents: balances[$0.id, default: 0]) })
        }
        return result
    }
}
