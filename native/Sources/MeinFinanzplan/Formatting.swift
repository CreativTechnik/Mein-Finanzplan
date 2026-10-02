import Foundation
import SwiftUI
import FinanceCore

enum EntryFormat {
    static func signedAmount(_ entry: FinanceEntry) -> String {
        signedAmount(cents: entry.amountCents, kind: entry.kind)
    }

    static func signedAmount(cents: Int, kind: EntryKind) -> String {
        let sign = kind == .expense ? "-" : kind == .income ? "+" : "→"
        return "\(sign) \(Money.string(cents))"
    }

    static func amountColor(_ entry: FinanceEntry) -> Color {
        amountColor(kind: entry.kind)
    }

    static func amountColor(kind: EntryKind) -> Color {
        switch kind {
        case .income: Theme.paleGreenText
        case .expense: Theme.paleRedText
        case .transfer: Theme.paleBlueText
        }
    }
}

enum Money {
    static func string(_ cents: Int) -> String {
        formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents)"
    }

    /// Whole-euro form for tight spaces such as the menu bar.
    static func compactString(_ cents: Int) -> String {
        compactFormatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents / 100) €"
    }

    private static let formatter: NumberFormatter = {
        let value = NumberFormatter()
        value.numberStyle = .currency
        value.locale = Locale(identifier: "de_DE")
        value.currencyCode = "EUR"
        return value
    }()

    private static let compactFormatter: NumberFormatter = {
        let value = NumberFormatter()
        value.numberStyle = .currency
        value.locale = Locale(identifier: "de_DE")
        value.currencyCode = "EUR"
        value.maximumFractionDigits = 0
        return value
    }()
}

enum DateText {
    /// User-facing date including the abbreviated weekday. Keep this separate
    /// from `string(_ date:)`, which intentionally remains the ISO storage
    /// representation used by FinanceCore.
    static func string(_ isoDate: String) -> String {
        guard let date = iso.date(from: isoDate) else { return isoDate }
        return userFacingDate(date)
    }

    static func display(_ date: Date) -> String {
        userFacingDate(date)
    }

    static func dateValue(_ isoDate: String) -> Date {
        iso.date(from: isoDate) ?? Date()
    }

    static func string(_ date: Date) -> String {
        iso.string(from: date)
    }

    static func weekday(_ isoDate: String) -> String {
        guard let date = iso.date(from: isoDate) else { return isoDate }
        return userFacingDate(date)
    }

    static func shortWeekday(_ date: Date) -> String {
        shortWeekdayFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    static func monthLabel(_ month: String) -> String {
        guard let date = monthKey.date(from: month) else { return month }
        return monthDisplay.string(from: date)
    }

    static func shortMonthLabel(_ month: String) -> String {
        guard let date = monthKey.date(from: month) else { return month }
        return shortMonthDisplay.string(from: date)
    }

    static func monthString(_ date: Date) -> String {
        monthKey.string(from: date)
    }

    static func chartAxis(_ date: Date, compact: Bool) -> String {
        compact ? axisMonth.string(from: date) : "\(shortWeekday(date)), \(axisDayMonth.string(from: date))"
    }

    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }
    static func dayNumber(_ date: Date) -> String { "\(shortWeekday(date)) \(dayNumberFormatter.string(from: date))" }
    static func shortDate(_ date: Date) -> String { "\(shortWeekday(date)), \(shortDateFormatter.string(from: date))" }
    static func shortMonth(_ date: Date) -> String { axisMonth.string(from: date) }

    private static let iso: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()

    private static let numericDateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "de_DE")
        value.dateFormat = "dd.MM.yyyy"
        return value
    }()

    private static let monthKey: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "yyyy-MM"
        return value
    }()

    private static let monthDisplay: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "de_DE")
        value.dateFormat = "MMMM yyyy"
        return value
    }()

    private static let shortMonthDisplay: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "de_DE")
        value.dateFormat = "MMM"
        return value
    }()

    private static let axisMonth: DateFormatter = formatter("MMM")
    private static let axisDayMonth: DateFormatter = formatter("d. MMM")
    private static let shortDayFormatter: DateFormatter = formatter("EE")
    private static let shortWeekdayFormatter: DateFormatter = formatter("EE")
    private static let dayNumberFormatter: DateFormatter = formatter("d.")
    private static let shortDateFormatter: DateFormatter = formatter("d. MMM")

    private static func userFacingDate(_ date: Date) -> String {
        "\(shortWeekday(date)), \(numericDateFormatter.string(from: date))"
    }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "de_DE")
        value.dateFormat = pattern
        return value
    }
}
