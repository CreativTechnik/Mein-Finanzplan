import Foundation

/// Calendar-bound period kinds shared by every chart and list in the app, so
/// "Quartal", "6 Monate" and "Jahr" always mean the same real calendar range
/// regardless of which screen renders them.
public enum CalendarPeriodKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case day
    case week
    case month
    case quarter
    case halfYear
    case year
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        case .quarter: "Quartal"
        case .halfYear: "6 Monate"
        case .year: "Jahr"
        case .custom: "Zeitraum"
        }
    }
}

/// A concrete, navigable calendar period: an inclusive `[startDate, endDate]`
/// range plus the kind it was derived from (so "next"/"previous" know how far
/// to step).
public struct CalendarPeriod: Hashable, Sendable {
    public let kind: CalendarPeriodKind
    public let startDate: String
    public let endDate: String

    public init(kind: CalendarPeriodKind, startDate: String, endDate: String) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
    }

    public var label: String { CalendarPeriodEngine.label(for: self) }
}

public enum CalendarPeriodError: Error, LocalizedError, Sendable {
    case invalidRange

    public var errorDescription: String? {
        switch self {
        case .invalidRange: "Das Enddatum muss am oder nach dem Startdatum liegen."
        }
    }
}

public enum CalendarPeriodEngine {
    /// The calendar period of `kind` that contains `date`.
    public static func period(kind: CalendarPeriodKind, containing date: String) -> CalendarPeriod {
        switch kind {
        case .day:
            return CalendarPeriod(kind: .day, startDate: date, endDate: date)
        case .week:
            let start = FinanceCalendar.startOfWeek(containing: date)
            return CalendarPeriod(kind: .week, startDate: start, endDate: FinanceCalendar.addingDays(6, to: start))
        case .month:
            let start = FinanceCalendar.startOfMonth(containing: date)
            return CalendarPeriod(kind: .month, startDate: start, endDate: FinanceCalendar.endOfMonth(containing: start))
        case .quarter:
            let start = FinanceCalendar.startOfQuarter(containing: date)
            return CalendarPeriod(kind: .quarter, startDate: start, endDate: FinanceCalendar.endOfQuarter(containing: start))
        case .halfYear:
            let start = FinanceCalendar.startOfHalfYear(containing: date)
            return CalendarPeriod(kind: .halfYear, startDate: start, endDate: FinanceCalendar.endOfHalfYear(containing: start))
        case .year:
            let start = FinanceCalendar.startOfYear(containing: date)
            return CalendarPeriod(kind: .year, startDate: start, endDate: FinanceCalendar.endOfYear(containing: start))
        case .custom:
            return CalendarPeriod(kind: .custom, startDate: date, endDate: date)
        }
    }

    /// A user-defined range. Rejects an end before the start rather than
    /// silently swapping or clamping it.
    public static func custom(start: String, end: String) throws -> CalendarPeriod {
        guard start <= end else { throw CalendarPeriodError.invalidRange }
        return CalendarPeriod(kind: .custom, startDate: start, endDate: end)
    }

    public static func next(_ period: CalendarPeriod) -> CalendarPeriod {
        switch period.kind {
        case .day: self.period(kind: .day, containing: FinanceCalendar.addingDays(1, to: period.startDate))
        case .week: self.period(kind: .week, containing: FinanceCalendar.addingDays(7, to: period.startDate))
        case .month: self.period(kind: .month, containing: FinanceCalendar.addingMonths(1, to: period.startDate, anchorDay: 1))
        case .quarter: self.period(kind: .quarter, containing: FinanceCalendar.addingMonths(3, to: period.startDate, anchorDay: 1))
        case .halfYear: self.period(kind: .halfYear, containing: FinanceCalendar.addingMonths(6, to: period.startDate, anchorDay: 1))
        case .year: self.period(kind: .year, containing: FinanceCalendar.addingMonths(12, to: period.startDate, anchorDay: 1))
        case .custom: shiftedCustom(period, by: 1)
        }
    }

    public static func previous(_ period: CalendarPeriod) -> CalendarPeriod {
        switch period.kind {
        case .day: self.period(kind: .day, containing: FinanceCalendar.addingDays(-1, to: period.startDate))
        case .week: self.period(kind: .week, containing: FinanceCalendar.addingDays(-7, to: period.startDate))
        case .month: self.period(kind: .month, containing: FinanceCalendar.addingMonths(-1, to: period.startDate, anchorDay: 1))
        case .quarter: self.period(kind: .quarter, containing: FinanceCalendar.addingMonths(-3, to: period.startDate, anchorDay: 1))
        case .halfYear: self.period(kind: .halfYear, containing: FinanceCalendar.addingMonths(-6, to: period.startDate, anchorDay: 1))
        case .year: self.period(kind: .year, containing: FinanceCalendar.addingMonths(-12, to: period.startDate, anchorDay: 1))
        case .custom: shiftedCustom(period, by: -1)
        }
    }

    private static func shiftedCustom(_ period: CalendarPeriod, by direction: Int) -> CalendarPeriod {
        let span = FinanceCalendar.daysBetween(period.startDate, period.endDate) + 1
        let offset = span * direction
        return CalendarPeriod(
            kind: .custom,
            startDate: FinanceCalendar.addingDays(offset, to: period.startDate),
            endDate: FinanceCalendar.addingDays(offset, to: period.endDate)
        )
    }

    public static func label(for period: CalendarPeriod) -> String {
        switch period.kind {
        case .day:
            return displayDate(FinanceCalendar.date(period.startDate) ?? Date(), formatter: germanFullDay)
        case .week:
            let start = FinanceCalendar.date(period.startDate) ?? Date()
            let end = FinanceCalendar.date(period.endDate) ?? Date()
            return "\(displayDate(start, formatter: germanDayMonth)) – \(displayDate(end, formatter: germanFullDay))"
        case .month:
            return germanMonthYear.string(from: FinanceCalendar.date(period.startDate) ?? Date())
        case .quarter:
            let components = FinanceCalendar.yearMonth(period.startDate)
            let quarter = (components.month - 1) / 3 + 1
            return "Q\(quarter) \(components.year)"
        case .halfYear:
            let components = FinanceCalendar.yearMonth(period.startDate)
            let half = components.month <= 6 ? 1 : 2
            return "\(half). Halbjahr \(components.year)"
        case .year:
            return String(FinanceCalendar.yearMonth(period.startDate).year)
        case .custom:
            let start = FinanceCalendar.date(period.startDate) ?? Date()
            let end = FinanceCalendar.date(period.endDate) ?? Date()
            return "\(displayDate(start, formatter: germanShortDate)) – \(displayDate(end, formatter: germanShortDate))"
        }
    }

    private static let germanFullDay: DateFormatter = formatter("d. MMM yyyy")
    private static let germanDayMonth: DateFormatter = formatter("d. MMM")
    private static let germanMonthYear: DateFormatter = formatter("MMMM yyyy")
    private static let germanShortDate: DateFormatter = formatter("dd.MM.yyyy")
    private static let germanWeekday: DateFormatter = formatter("EE")

    private static func displayDate(_ date: Date, formatter: DateFormatter) -> String {
        let weekday = germanWeekday.string(from: date).replacingOccurrences(of: ".", with: "")
        return "\(weekday), \(formatter.string(from: date))"
    }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "de_DE")
        value.timeZone = FinanceCalendar.timeZone
        value.dateFormat = pattern
        return value
    }
}
