import Foundation

public enum TextNormalizer {
    /// Case, diacritics, punctuation and whitespace insensitive form used to
    /// compare bank texts with manually typed titles.
    public static func normalized(_ value: String) -> String {
        let folded = value
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
        var result = ""
        var previousWasSpace = true
        for character in folded {
            if character.isLetter || character.isNumber {
                result.append(character)
                previousWasSpace = false
            } else if !previousWasSpace {
                result.append(" ")
                previousWasSpace = true
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

public struct ImportDuplicateMatch: Hashable, Sendable {
    public enum Level: Hashable, Sendable {
        /// Same account, direction, amount, day and matching text.
        case certain
        /// Same amount and direction close to the date, or a planned entry.
        case possible
    }

    public let level: Level
    public let entryID: String?

    public init(level: Level, entryID: String?) {
        self.level = level
        self.entryID = entryID
    }
}

public enum ImportDuplicateDetector {
    public static let defaultDateTolerance = 3

    /// Compares every candidate against existing entries. Each existing entry
    /// can explain at most one candidate, so two identical bank rows against a
    /// single stored booking yield one duplicate and one new row.
    public static func detect(
        _ candidates: [BankImportEntry],
        existing: [FinanceEntry],
        knownFingerprints: Set<String> = [],
        dateTolerance: Int = defaultDateTolerance
    ) -> [ImportDuplicateMatch?] {
        var buckets: [String: [FinanceEntry]] = [:]
        for entry in existing where entry.status != .cancelled {
            buckets[key(account: entry.accountID, kind: entry.kind, transfer: entry.transferAccountID, amount: entry.amountCents), default: []].append(entry)
        }

        var results = [ImportDuplicateMatch?](repeating: nil, count: candidates.count)
        var consumed = Set<String>()
        let normalizedTitles = candidates.map { TextNormalizer.normalized($0.title) }

        for (index, candidate) in candidates.enumerated() {
            if let fingerprint = candidate.fingerprint, knownFingerprints.contains(fingerprint) {
                results[index] = ImportDuplicateMatch(level: .certain, entryID: nil)
            }
        }

        for (index, candidate) in candidates.enumerated() where results[index] == nil {
            let bucket = buckets[key(for: candidate)] ?? []
            let match = bucket
                .filter { $0.status == .booked && !consumed.contains($0.id) && datesMatch($0, candidate.date) && textsMatch(normalizedTitles[index], TextNormalizer.normalized($0.title)) }
                .first
            if let match {
                consumed.insert(match.id)
                results[index] = ImportDuplicateMatch(level: .certain, entryID: match.id)
            }
        }

        for (index, candidate) in candidates.enumerated() where results[index] == nil {
            let bucket = buckets[key(for: candidate)] ?? []
            let match = bucket
                .filter { !consumed.contains($0.id) }
                .compactMap { entry -> (FinanceEntry, Int)? in
                    let distance = dayDistance(entry, candidate.date)
                    return distance <= dateTolerance ? (entry, distance) : nil
                }
                .min { $0.1 < $1.1 }
            if let match {
                consumed.insert(match.0.id)
                results[index] = ImportDuplicateMatch(level: .possible, entryID: match.0.id)
            }
        }
        return results
    }

    private static func key(for candidate: BankImportEntry) -> String {
        key(account: candidate.accountID, kind: candidate.kind, transfer: candidate.transferAccountID, amount: candidate.amountCents)
    }

    private static func key(account: String, kind: EntryKind, transfer: String?, amount: Int) -> String {
        "\(account)|\(kind.rawValue)|\(transfer ?? "")|\(amount)"
    }

    private static func datesMatch(_ entry: FinanceEntry, _ date: String) -> Bool {
        entry.plannedDate == date || entry.actualDate == date
    }

    private static func dayDistance(_ entry: FinanceEntry, _ date: String) -> Int {
        let dates = [entry.plannedDate, entry.actualDate].compactMap { $0 }
        return dates.map { daysBetween($0, date) }.min() ?? Int.max
    }

    private static func daysBetween(_ first: String, _ second: String) -> Int {
        guard let left = FinanceCalendar.date(first), let right = FinanceCalendar.date(second) else { return Int.max }
        return Int((abs(left.timeIntervalSince(right)) / 86_400).rounded())
    }

    private static func textsMatch(_ candidate: String, _ stored: String) -> Bool {
        guard !candidate.isEmpty, !stored.isEmpty else { return false }
        if candidate == stored { return true }
        let (shorter, longer) = candidate.count <= stored.count ? (candidate, stored) : (stored, candidate)
        return shorter.count >= 3 && longer.contains(shorter)
    }
}
