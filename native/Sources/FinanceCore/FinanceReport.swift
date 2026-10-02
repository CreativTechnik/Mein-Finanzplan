import Foundation
import AppKit
import CoreGraphics

public enum FinanceReportGenerator {
    private static let reportText = NSColor(red: 0.08, green: 0.12, blue: 0.17, alpha: 1)
    private static let reportSecondary = NSColor(red: 0.35, green: 0.40, blue: 0.46, alpha: 1)
    public static func pdfData(snapshot: FinanceSnapshot, startDate: String, endDate: String, accountID: String?) throws -> Data {
        let start = FinanceCalendar.date(startDate)
        guard let inclusiveEnd = FinanceCalendar.date(endDate), let start else {
            throw FinanceDatabaseError.invalid("Der Berichtszeitraum ist ungültig.")
        }
        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
        let generatedEntries = FinanceEngine.occurrencesAndEntries(
            entries: snapshot.entries,
            rules: snapshot.rules,
            today: snapshot.today,
            start: startDate,
            end: endDate
        )
        let entries = generatedEntries.filter { entry in
            guard entry.status != .cancelled,
                  let date = FinanceCalendar.date(entry.actualDate ?? entry.plannedDate), date >= start, date < end else { return false }
            guard let accountID else { return entry.kind != .transfer }
            return entry.accountID == accountID || entry.transferAccountID == accountID
        }

        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FinanceDatabaseError.invalid("Der PDF-Bericht konnte nicht erzeugt werden.")
        }
        let accountName = accountID.flatMap { id in snapshot.accounts.first(where: { $0.id == id })?.name } ?? "Alle Konten"
        let totals = totals(entries: entries, accountID: accountID)
        let timeline = FinanceEngine.timeline(
            accounts: snapshot.accounts,
            entries: snapshot.entries,
            rules: snapshot.rules,
            today: snapshot.today,
            start: startDate,
            end: endDate
        ).filter { accountID == nil || $0.accountID == accountID }
        drawOverviewPage(context: context, box: mediaBox, snapshot: snapshot, startDate: startDate, endDate: endDate, accountName: accountName, timeline: timeline, totals: totals)
        drawFlowPage(context: context, box: mediaBox, startDate: startDate, endDate: endDate, entries: entries)
        drawCategoryPage(context: context, box: mediaBox, snapshot: snapshot, startDate: startDate, endDate: endDate, entries: entries, accountID: accountID)
        context.closePDF()
        return data as Data
    }

    public static func writePDF(snapshot: FinanceSnapshot, startDate: String, endDate: String, accountID: String?, to url: URL) throws {
        try pdfData(snapshot: snapshot, startDate: startDate, endDate: endDate, accountID: accountID).write(to: url, options: .atomic)
    }

    private static func totals(entries: [FinanceEntry], accountID: String?) -> (income: Int, expense: Int, plannedIncome: Int, plannedExpense: Int) {
        var result = (0, 0, 0, 0)
        for entry in entries {
            var kind = entry.kind
            if entry.kind == .transfer, let accountID {
                kind = entry.transferAccountID == accountID ? .income : .expense
            }
            if kind == .income {
                result.0 += entry.amountCents
                if entry.status == .planned { result.2 += entry.amountCents }
            } else if kind == .expense {
                result.1 += entry.amountCents
                if entry.status == .planned { result.3 += entry.amountCents }
            }
        }
        return result
    }

    private static func drawOverviewPage(context: CGContext, box: CGRect, snapshot: FinanceSnapshot, startDate: String, endDate: String, accountName: String, timeline: [ForecastPoint], totals: (income: Int, expense: Int, plannedIncome: Int, plannedExpense: Int)) {
        beginPage(context, box: box)
        title("Mein Finanzplan", at: CGPoint(x: 48, y: 772), size: 25)
        text("Finanzbericht · \(displayDate(startDate)) bis \(displayDate(endDate))", at: CGPoint(x: 48, y: 744), size: 12, color: reportSecondary)
        pill(accountName, rect: CGRect(x: 408, y: 742, width: 139, height: 28))

        metric("Einnahmen", cents: totals.income, detail: "davon geplant \(money(totals.plannedIncome))", color: NSColor(red: 0.20, green: 0.55, blue: 0.43, alpha: 1), rect: CGRect(x: 48, y: 642, width: 154, height: 76))
        metric("Ausgaben", cents: totals.expense, detail: "davon geplant \(money(totals.plannedExpense))", color: NSColor(red: 0.73, green: 0.31, blue: 0.30, alpha: 1), rect: CGRect(x: 220, y: 642, width: 154, height: 76))
        metric("Differenz", cents: totals.income - totals.expense, detail: "Ist und Planung", color: NSColor(red: 0.17, green: 0.43, blue: 0.66, alpha: 1), rect: CGRect(x: 392, y: 642, width: 155, height: 76))

        text("LIQUIDITÄTSVERLAUF", at: CGPoint(x: 48, y: 596), size: 10, weight: .semibold, color: reportSecondary)
        let chartRect = CGRect(x: 48, y: 286, width: 499, height: 286)
        drawLiquidityChart(points: timeline, accounts: snapshot.accounts, rect: chartRect)
        text("Kontostand je Konto · historische und geplante Werte", at: CGPoint(x: 48, y: 262), size: 10, color: reportSecondary)
        footer(context, page: 1)
        endPage(context)
    }

    private static func drawFlowPage(context: CGContext, box: CGRect, startDate: String, endDate: String, entries: [FinanceEntry]) {
        beginPage(context, box: box)
        title("Einnahmen und Ausgaben", at: CGPoint(x: 48, y: 772), size: 23)
        text("Statistischer Verlauf · \(displayDate(startDate)) bis \(displayDate(endDate))", at: CGPoint(x: 48, y: 744), size: 12, color: reportSecondary)
        text("FINANZFLUSS", at: CGPoint(x: 48, y: 684), size: 10, weight: .semibold, color: reportSecondary)
        drawChart(entries: entries, rect: CGRect(x: 48, y: 330, width: 499, height: 326))
        text("Grün: Einnahmen · Rot: Ausgaben · geplante Werte eingeschlossen", at: CGPoint(x: 48, y: 302), size: 10, color: reportSecondary)
        footer(context, page: 2)
        endPage(context)
    }

    private static func drawCategoryPage(context: CGContext, box: CGRect, snapshot: FinanceSnapshot, startDate: String, endDate: String, entries: [FinanceEntry], accountID: String?) {
        beginPage(context, box: box)
        title("Kategorien", at: CGPoint(x: 48, y: 772), size: 23)
        text("Zusammenfassung · \(displayDate(startDate)) bis \(displayDate(endDate))", at: CGPoint(x: 48, y: 744), size: 12, color: reportSecondary)
        let categoryNames = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0.name) })
        let income = categoryTotals(entries: entries, kind: .income, accountID: accountID, names: categoryNames)
        let expense = categoryTotals(entries: entries, kind: .expense, accountID: accountID, names: categoryNames)
        text("AUSGABENANTEILE", at: CGPoint(x: 48, y: 700), size: 10, weight: .semibold, color: reportSecondary)
        drawDonut(rows: expense, rect: CGRect(x: 207, y: 520, width: 180, height: 180))
        categoryColumn("EINNAHMEN", rows: income, x: 48, startY: 440, color: NSColor(red: 0.20, green: 0.55, blue: 0.43, alpha: 1))
        categoryColumn("AUSGABEN", rows: expense, x: 309, startY: 440, color: NSColor(red: 0.73, green: 0.31, blue: 0.30, alpha: 1))
        footer(context, page: 3)
        endPage(context)
    }

    private static func categoryTotals(entries: [FinanceEntry], kind requested: EntryKind, accountID: String?, names: [String: String]) -> [(String, Int)] {
        var grouped: [String: Int] = [:]
        for entry in entries {
            var kind = entry.kind
            if entry.kind == .transfer, let accountID { kind = entry.transferAccountID == accountID ? .income : .expense }
            guard kind == requested else { continue }
            grouped[names[entry.categoryID ?? ""] ?? (entry.kind == .transfer ? "Umbuchungen" : "Ohne Kategorie"), default: 0] += entry.amountCents
        }
        return grouped.sorted { $0.value > $1.value }
    }

    private static func drawChart(entries: [FinanceEntry], rect: CGRect) {
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        let months = Dictionary(grouping: entries) { String(($0.actualDate ?? $0.plannedDate).prefix(7)) }.sorted { $0.key < $1.key }
        guard !months.isEmpty else { text("Keine Werte im Zeitraum", at: CGPoint(x: rect.midX - 55, y: rect.midY), size: 11, color: reportSecondary); return }
        let values = months.map { month in totals(entries: month.value.filter { $0.kind != .transfer }, accountID: nil) }
        let maximum = max(1, values.map { max($0.income, $0.expense) }.max() ?? 1)
        let slot = rect.width / CGFloat(months.count)
        for index in months.indices {
            let baseX = rect.minX + CGFloat(index) * slot + slot * 0.18
            let usableHeight = rect.height - 48
            let incomeHeight = usableHeight * CGFloat(values[index].income) / CGFloat(maximum)
            let expenseHeight = usableHeight * CGFloat(values[index].expense) / CGFloat(maximum)
            NSColor(red: 0.20, green: 0.55, blue: 0.43, alpha: 0.88).setFill()
            NSBezierPath(roundedRect: CGRect(x: baseX, y: rect.minY + 28, width: max(6, slot * 0.25), height: incomeHeight), xRadius: 3, yRadius: 3).fill()
            NSColor(red: 0.73, green: 0.31, blue: 0.30, alpha: 0.88).setFill()
            NSBezierPath(roundedRect: CGRect(x: baseX + slot * 0.29, y: rect.minY + 28, width: max(6, slot * 0.25), height: expenseHeight), xRadius: 3, yRadius: 3).fill()
            text(monthLabel(months[index].key), at: CGPoint(x: baseX, y: rect.minY + 9), size: 8, color: reportSecondary)
        }
    }

    private static func drawLiquidityChart(points: [ForecastPoint], accounts: [Account], rect: CGRect) {
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        guard !points.isEmpty else {
            text("Keine Kontostandswerte im Zeitraum", at: CGPoint(x: rect.midX - 85, y: rect.midY), size: 11, color: reportSecondary)
            return
        }
        let values = points.map(\.balanceCents)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let span = max(1, maximum - minimum)
        let grouped = Dictionary(grouping: points, by: \.accountID)
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let plot = rect.insetBy(dx: 18, dy: 34)
        var legendX = rect.minX + 16
        for account in accounts where grouped[account.id] != nil {
            let series = (grouped[account.id] ?? []).sorted { $0.date < $1.date }
            guard series.count > 1 else { continue }
            let path = NSBezierPath()
            for (index, point) in series.enumerated() {
                let x = plot.minX + plot.width * CGFloat(index) / CGFloat(max(1, series.count - 1))
                let y = plot.minY + plot.height * CGFloat(point.balanceCents - minimum) / CGFloat(span)
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.line(to: CGPoint(x: x, y: y))
            }
            let color = reportColor(hex: account.colorHex)
            color.setStroke(); path.lineWidth = 2; path.stroke()
            color.setFill(); NSBezierPath(ovalIn: CGRect(x: legendX, y: rect.maxY - 20, width: 7, height: 7)).fill()
            text(accountMap[account.id]?.name ?? account.name, at: CGPoint(x: legendX + 11, y: rect.maxY - 23), size: 8, color: reportSecondary)
            legendX += min(120, CGFloat(account.name.count * 6 + 28))
        }
    }

    private static func drawDonut(rows: [(String, Int)], rect: CGRect) {
        let total = rows.reduce(0) { $0 + $1.1 }
        guard total > 0 else {
            text("Keine Ausgaben", at: CGPoint(x: rect.midX - 34, y: rect.midY), size: 10, color: reportSecondary)
            return
        }
        let palette = [
            NSColor(red: 0.17, green: 0.43, blue: 0.66, alpha: 1),
            NSColor(red: 0.73, green: 0.31, blue: 0.30, alpha: 1),
            NSColor(red: 0.20, green: 0.55, blue: 0.43, alpha: 1),
            NSColor(red: 0.47, green: 0.39, blue: 0.62, alpha: 1),
            NSColor(red: 0.64, green: 0.49, blue: 0.25, alpha: 1),
            NSColor(red: 0.35, green: 0.48, blue: 0.58, alpha: 1)
        ]
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var start = -CGFloat.pi / 2
        for (index, row) in rows.enumerated() {
            let angle = CGFloat(row.1) / CGFloat(total) * CGFloat.pi * 2
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: radius, startAngle: start * 180 / .pi, endAngle: (start + angle) * 180 / .pi)
            path.close()
            palette[index % palette.count].setFill(); path.fill()
            start += angle
        }
        NSColor.white.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 48, dy: 48)).fill()
        centeredText(money(total), rect: rect.insetBy(dx: 30, dy: 70), size: 12, weight: .semibold)
    }

    private static func categoryColumn(_ heading: String, rows: [(String, Int)], x: CGFloat, startY: CGFloat, color: NSColor) {
        text(heading, at: CGPoint(x: x, y: startY), size: 10, weight: .semibold, color: color)
        var y = startY - 38
        let shown = rows.prefix(9)
        for (index, row) in shown.enumerated() {
            if index % 2 == 0 { NSColor(calibratedWhite: 0.965, alpha: 1).setFill(); NSBezierPath(roundedRect: CGRect(x: x, y: y - 9, width: 238, height: 30), xRadius: 6, yRadius: 6).fill() }
            text(row.0, at: CGPoint(x: x + 9, y: y), size: 10)
            rightText(money(row.1), right: x + 229, y: y, size: 10, weight: .semibold)
            y -= 36
        }
        if shown.isEmpty { text("Keine Werte", at: CGPoint(x: x + 9, y: y), size: 10, color: reportSecondary) }
    }

    private static func beginPage(_ context: CGContext, box: CGRect) {
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill(); context.fill(box)
    }
    private static func endPage(_ context: CGContext) { NSGraphicsContext.current = nil; context.endPDFPage() }
    private static func footer(_ context: CGContext, page: Int) {
        NSColor(calibratedWhite: 0.88, alpha: 1).setStroke(); let path = NSBezierPath(); path.move(to: CGPoint(x: 48, y: 52)); path.line(to: CGPoint(x: 547, y: 52)); path.stroke()
        text("© 2026 CreativTechnik · Mein Finanzplan", at: CGPoint(x: 48, y: 31), size: 8, color: reportSecondary)
        rightText("Seite \(page)", right: 547, y: 31, size: 8, color: reportSecondary)
    }

    private static func metric(_ label: String, cents: Int, detail: String, color: NSColor, rect: CGRect) {
        NSColor(calibratedWhite: 0.965, alpha: 1).setFill(); NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        text(label, at: CGPoint(x: rect.minX + 12, y: rect.maxY - 23), size: 9, color: reportSecondary)
        text(money(cents), at: CGPoint(x: rect.minX + 12, y: rect.maxY - 48), size: 16, weight: .semibold, color: color)
        text(detail, at: CGPoint(x: rect.minX + 12, y: rect.minY + 9), size: 7.5, color: reportSecondary)
    }
    private static func pill(_ value: String, rect: CGRect) { NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill(); centeredText(value, rect: rect, size: 9, weight: .medium) }
    private static func title(_ value: String, at point: CGPoint, size: CGFloat) { text(value, at: point, size: size, weight: .bold) }
    private static func text(_ value: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = reportText) {
        (value as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
    private static func rightText(_ value: String, right: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = reportText) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let width = (value as NSString).size(withAttributes: attributes).width
        (value as NSString).draw(at: CGPoint(x: right - width, y: y), withAttributes: attributes)
    }
    private static func centeredText(_ value: String, rect: CGRect, size: CGFloat, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: reportText]
        let sizeValue = (value as NSString).size(withAttributes: attributes)
        (value as NSString).draw(at: CGPoint(x: rect.midX - sizeValue.width / 2, y: rect.midY - sizeValue.height / 2), withAttributes: attributes)
    }
    private static func money(_ cents: Int) -> String { let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "EUR"; f.locale = Locale(identifier: "de_DE"); return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "–" }
    private static func displayDate(_ value: String) -> String {
        guard let date = FinanceCalendar.date(value) else { return value }
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "de_DE")
        weekday.timeZone = FinanceCalendar.timeZone
        weekday.dateFormat = "EE"
        let numericDate = DateFormatter()
        numericDate.locale = Locale(identifier: "de_DE")
        numericDate.timeZone = FinanceCalendar.timeZone
        numericDate.dateFormat = "dd.MM.yyyy"
        let weekdayText = weekday.string(from: date).replacingOccurrences(of: ".", with: "")
        return "\(weekdayText), \(numericDate.string(from: date))"
    }
    private static func monthLabel(_ value: String) -> String { let parts = value.split(separator: "-"); guard parts.count == 2, let month = Int(parts[1]) else { return value }; let names = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]; return "\(names[max(0, min(11, month - 1))]) \(parts[0].suffix(2))" }
    private static func reportColor(hex: String) -> NSColor {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return .systemBlue }
        return NSColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
