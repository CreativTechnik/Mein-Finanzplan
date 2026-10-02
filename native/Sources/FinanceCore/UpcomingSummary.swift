import Foundation

public enum UpcomingSummary {
    /// The next open bookings within `days` from `today`, oldest first. Already
    /// booked and cancelled entries are excluded because they no longer need
    /// attention.
    public static func entries(in items: [FinanceEntry], today: String, days: Int = 14, limit: Int = 5) -> [FinanceEntry] {
        let end = FinanceCalendar.addingDays(days, to: today)
        return items
            .filter { $0.status == .planned && $0.plannedDate >= today && $0.plannedDate <= end }
            .sorted { $0.plannedDate == $1.plannedDate ? $0.title < $1.title : $0.plannedDate < $1.plannedDate }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
