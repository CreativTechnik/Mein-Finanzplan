import Foundation

public enum AccountKind: String, CaseIterable, Codable, Sendable {
    case checking = "CHECKING"
    case savings = "SAVINGS"
    case cash = "CASH"
    case other = "OTHER"

    public var label: String {
        switch self {
        case .checking: "Girokonto"
        case .savings: "Sparen"
        case .cash: "Bargeld"
        case .other: "Sonstiges"
        }
    }
}

public enum EntryKind: String, CaseIterable, Codable, Sendable {
    case income = "INCOME"
    case expense = "EXPENSE"
    case transfer = "TRANSFER"

    public var label: String {
        switch self {
        case .income: "Einnahme"
        case .expense: "Ausgabe"
        case .transfer: "Umbuchung"
        }
    }
}

public enum EntryStatus: String, CaseIterable, Codable, Sendable {
    case planned = "PLANNED"
    case booked = "BOOKED"
    case cancelled = "CANCELLED"

    public var label: String {
        switch self {
        case .planned: "Geplant"
        case .booked: "Gebucht"
        case .cancelled: "Storniert"
        }
    }
}

public enum RecurrenceFrequency: String, CaseIterable, Codable, Sendable {
    case monthly = "MONTHLY"
    case weekly = "WEEKLY"
    case yearly = "YEARLY"

    public var label: String {
        switch self {
        case .monthly: "Monatlich"
        case .weekly: "Wöchentlich"
        case .yearly: "Jährlich"
        }
    }
}

public struct Account: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var kind: AccountKind
    public var currentBalanceCents: Int
    public var balanceAsOf: String
    public var minimumBufferCents: Int
    public var colorHex: String
    public var isPrimary: Bool
    public var needsReview: Bool

    public init(id: String, name: String, kind: AccountKind, currentBalanceCents: Int, balanceAsOf: String, minimumBufferCents: Int, colorHex: String, isPrimary: Bool, needsReview: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currentBalanceCents = currentBalanceCents
        self.balanceAsOf = balanceAsOf
        self.minimumBufferCents = minimumBufferCents
        self.colorHex = colorHex
        self.isPrimary = isPrimary
        self.needsReview = needsReview
    }
}

public struct FinanceCategory: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var kind: EntryKind
    public var iconName: String

    public init(id: String, name: String, kind: EntryKind, iconName: String = "tag") {
        self.id = id
        self.name = name
        self.kind = kind
        self.iconName = iconName
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, iconName
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(EntryKind.self, forKey: .kind)
        iconName = try values.decodeIfPresent(String.self, forKey: .iconName) ?? "tag"
    }
}

public struct FinanceEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var title: String
    public var amountCents: Int
    public var kind: EntryKind
    public var accountID: String
    public var transferAccountID: String?
    public var categoryID: String?
    public var recurrenceID: String?
    public var plannedDate: String
    public var actualDate: String?
    public var status: EntryStatus
    public var note: String?
    public var isReliable: Bool
    public var affectsBalance: Bool
    public var isArchived: Bool

    public init(id: String, title: String, amountCents: Int, kind: EntryKind, accountID: String, transferAccountID: String? = nil, categoryID: String? = nil, recurrenceID: String? = nil, plannedDate: String, actualDate: String? = nil, status: EntryStatus = .planned, note: String? = nil, isReliable: Bool = false, affectsBalance: Bool = false, isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.amountCents = amountCents
        self.kind = kind
        self.accountID = accountID
        self.transferAccountID = transferAccountID
        self.categoryID = categoryID
        self.recurrenceID = recurrenceID
        self.plannedDate = plannedDate
        self.actualDate = actualDate
        self.status = status
        self.note = note
        self.isReliable = isReliable
        self.affectsBalance = affectsBalance
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amountCents, kind, accountID, transferAccountID, categoryID, recurrenceID
        case plannedDate, actualDate, status, note, isReliable, affectsBalance, isArchived
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        amountCents = try values.decode(Int.self, forKey: .amountCents)
        kind = try values.decode(EntryKind.self, forKey: .kind)
        accountID = try values.decode(String.self, forKey: .accountID)
        transferAccountID = try values.decodeIfPresent(String.self, forKey: .transferAccountID)
        categoryID = try values.decodeIfPresent(String.self, forKey: .categoryID)
        recurrenceID = try values.decodeIfPresent(String.self, forKey: .recurrenceID)
        plannedDate = try values.decode(String.self, forKey: .plannedDate)
        actualDate = try values.decodeIfPresent(String.self, forKey: .actualDate)
        status = try values.decode(EntryStatus.self, forKey: .status)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        isReliable = try values.decode(Bool.self, forKey: .isReliable)
        affectsBalance = try values.decode(Bool.self, forKey: .affectsBalance)
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

public struct BankImportEntry: Hashable, Sendable {
    public let title: String
    public let amountCents: Int
    public let kind: EntryKind
    public let accountID: String
    public let transferAccountID: String?
    public let categoryID: String?
    public let date: String
    public let fingerprint: String?

    public init(title: String, amountCents: Int, kind: EntryKind, accountID: String, transferAccountID: String? = nil, categoryID: String?, date: String, fingerprint: String? = nil) {
        self.title = title
        self.amountCents = amountCents
        self.kind = kind
        self.accountID = accountID
        self.transferAccountID = transferAccountID
        self.categoryID = categoryID
        self.date = date
        self.fingerprint = fingerprint
    }
}

/// A single absolute or relative change to a recurring rule's amount, effective
/// from a given date onward. Stages apply cumulatively in chronological order:
/// `.absolute` replaces the running amount, `.delta` adjusts it. This keeps
/// resolution deterministic and cent-exact regardless of how many stages exist.
public enum AmountAdjustment: Hashable, Sendable {
    case absolute(Int)
    case delta(Int)

    public var cents: Int {
        switch self {
        case .absolute(let cents): cents
        case .delta(let cents): cents
        }
    }
}

extension AmountAdjustment: Codable {
    private enum CodingKeys: String, CodingKey { case type, cents }
    private enum Kind: String, Codable { case absolute, delta }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absolute(let cents):
            try container.encode(Kind.absolute, forKey: .type)
            try container.encode(cents, forKey: .cents)
        case .delta(let cents):
            try container.encode(Kind.delta, forKey: .type)
            try container.encode(cents, forKey: .cents)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        let cents = try container.decode(Int.self, forKey: .cents)
        self = kind == .absolute ? .absolute(cents) : .delta(cents)
    }
}

public struct RecurringAmountStage: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var effectiveDate: String
    public var adjustment: AmountAdjustment

    public init(id: String = UUID().uuidString, effectiveDate: String, adjustment: AmountAdjustment) {
        self.id = id
        self.effectiveDate = effectiveDate
        self.adjustment = adjustment
    }
}

/// How a monthly recurring rule picks its date within a given month. Not tied to
/// any specific rule name (salary, child benefit, ...) so any recurring rule can
/// use whichever schedule matches its real-world payment terms.
public enum RecurrenceSchedule: Hashable, Sendable {
    /// A fixed calendar day (clamped to the month's last day). `nil` derives the
    /// day from the rule's `startDate`, matching the legacy anchor-day behavior.
    case fixedDay(Int?)
    /// A monthly date window, e.g. the 15th to the 25th. Liquidity planning is
    /// conservative: incomes are assumed on `endDay` (latest), expenses on
    /// `startDay` (earliest).
    case dateWindow(startDay: Int, endDay: Int)
    /// The latest occurrence of `weekday` on or before `deadlineDay` of the
    /// month. `weekday` uses `Calendar`'s numbering (1 = Sunday ... 7 = Saturday).
    case weekdayBeforeDeadline(weekday: Int, deadlineDay: Int)
    /// Explicit dates take precedence over the regular frequency. This is for
    /// payments whose concrete arrival date is known separately for each
    /// month or year and can be extended without changing the rule.
    case exactDates([String])
}

extension RecurrenceSchedule: Codable {
    private enum CodingKeys: String, CodingKey { case type, day, startDay, endDay, weekday, deadlineDay, dates }
    private enum Kind: String, Codable { case fixedDay, dateWindow, weekdayBeforeDeadline, exactDates }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixedDay(let day):
            try container.encode(Kind.fixedDay, forKey: .type)
            try container.encodeIfPresent(day, forKey: .day)
        case .dateWindow(let startDay, let endDay):
            try container.encode(Kind.dateWindow, forKey: .type)
            try container.encode(startDay, forKey: .startDay)
            try container.encode(endDay, forKey: .endDay)
        case .weekdayBeforeDeadline(let weekday, let deadlineDay):
            try container.encode(Kind.weekdayBeforeDeadline, forKey: .type)
            try container.encode(weekday, forKey: .weekday)
            try container.encode(deadlineDay, forKey: .deadlineDay)
        case .exactDates(let dates):
            try container.encode(Kind.exactDates, forKey: .type)
            try container.encode(dates, forKey: .dates)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .fixedDay:
            self = .fixedDay(try container.decodeIfPresent(Int.self, forKey: .day))
        case .dateWindow:
            self = .dateWindow(startDay: try container.decode(Int.self, forKey: .startDay), endDay: try container.decode(Int.self, forKey: .endDay))
        case .weekdayBeforeDeadline:
            self = .weekdayBeforeDeadline(weekday: try container.decode(Int.self, forKey: .weekday), deadlineDay: try container.decode(Int.self, forKey: .deadlineDay))
        case .exactDates:
            self = .exactDates(try container.decodeIfPresent([String].self, forKey: .dates) ?? [])
        }
    }
}

public struct RecurringRule: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var title: String
    public var amountCents: Int
    public var kind: EntryKind
    public var accountID: String
    public var transferAccountID: String?
    public var categoryID: String?
    public var frequency: RecurrenceFrequency
    public var interval: Int
    public var startDate: String
    public var endDate: String?
    public var schedule: RecurrenceSchedule
    public var amountStages: [RecurringAmountStage]
    public var excludedDates: [String]
    public var isReliable: Bool
    public var isActive: Bool
    public var needsReview: Bool

    public var dueDay: Int? {
        if case .fixedDay(let day) = schedule { return day }
        return nil
    }

    public init(id: String, title: String, amountCents: Int, kind: EntryKind, accountID: String, transferAccountID: String? = nil, categoryID: String? = nil, frequency: RecurrenceFrequency, interval: Int = 1, startDate: String, endDate: String? = nil, dueDay: Int? = nil, schedule: RecurrenceSchedule? = nil, amountStages: [RecurringAmountStage] = [], excludedDates: [String] = [], isReliable: Bool = false, isActive: Bool = true, needsReview: Bool = false) {
        self.id = id
        self.title = title
        self.amountCents = amountCents
        self.kind = kind
        self.accountID = accountID
        self.transferAccountID = transferAccountID
        self.categoryID = categoryID
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.schedule = schedule ?? .fixedDay(dueDay)
        self.amountStages = amountStages
        self.excludedDates = excludedDates
        self.isReliable = isReliable
        self.isActive = isActive
        self.needsReview = needsReview
    }

    /// Resolves the cent-exact amount effective on `date`, applying every
    /// staged change up to and including that date in chronological order.
    public func amountCents(on date: String) -> Int {
        var result = amountCents
        for stage in amountStages.sorted(by: { $0.effectiveDate < $1.effectiveDate }) where stage.effectiveDate <= date {
            switch stage.adjustment {
            case .absolute(let cents): result = cents
            case .delta(let cents): result += cents
            }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amountCents, kind, accountID, transferAccountID, categoryID
        case frequency, interval, startDate, endDate, dueDay, schedule, amountStages, excludedDates
        case isReliable, isActive, needsReview
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        amountCents = try values.decode(Int.self, forKey: .amountCents)
        kind = try values.decode(EntryKind.self, forKey: .kind)
        accountID = try values.decode(String.self, forKey: .accountID)
        transferAccountID = try values.decodeIfPresent(String.self, forKey: .transferAccountID)
        categoryID = try values.decodeIfPresent(String.self, forKey: .categoryID)
        frequency = try values.decode(RecurrenceFrequency.self, forKey: .frequency)
        interval = try values.decode(Int.self, forKey: .interval)
        startDate = try values.decode(String.self, forKey: .startDate)
        endDate = try values.decodeIfPresent(String.self, forKey: .endDate)
        if let decodedSchedule = try values.decodeIfPresent(RecurrenceSchedule.self, forKey: .schedule) {
            schedule = decodedSchedule
        } else {
            schedule = .fixedDay(try values.decodeIfPresent(Int.self, forKey: .dueDay))
        }
        amountStages = try values.decodeIfPresent([RecurringAmountStage].self, forKey: .amountStages) ?? []
        excludedDates = try values.decodeIfPresent([String].self, forKey: .excludedDates) ?? []
        isReliable = try values.decode(Bool.self, forKey: .isReliable)
        isActive = try values.decode(Bool.self, forKey: .isActive)
        needsReview = try values.decode(Bool.self, forKey: .needsReview)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(amountCents, forKey: .amountCents)
        try container.encode(kind, forKey: .kind)
        try container.encode(accountID, forKey: .accountID)
        try container.encodeIfPresent(transferAccountID, forKey: .transferAccountID)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(interval, forKey: .interval)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(schedule, forKey: .schedule)
        try container.encodeIfPresent(dueDay, forKey: .dueDay)
        try container.encode(amountStages, forKey: .amountStages)
        try container.encode(excludedDates, forKey: .excludedDates)
        try container.encode(isReliable, forKey: .isReliable)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(needsReview, forKey: .needsReview)
    }
}

public struct Budget: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var month: String
    public var categoryID: String
    public var plannedCents: Int
    public var actualCents: Int

    public init(id: String, month: String, categoryID: String, plannedCents: Int, actualCents: Int = 0) {
        self.id = id
        self.month = month
        self.categoryID = categoryID
        self.plannedCents = plannedCents
        self.actualCents = actualCents
    }
}

public struct ForecastPoint: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(date):\(accountID)" }
    public let date: String
    public let accountID: String
    public let balanceCents: Int

    public init(date: String, accountID: String, balanceCents: Int) {
        self.date = date
        self.accountID = accountID
        self.balanceCents = balanceCents
    }
}

public struct LiquidityResult: Hashable, Codable, Sendable {
    public let horizon: String
    public let availableCents: Int
    public let requiredCents: Int
    public let shortfallCents: Int
    public let weekRequiredCents: Int
    public let nextIncomeTitle: String?
    public let nextIncomeDate: String?
    public let nextIncomeCents: Int?
    public let firstRiskDate: String?

    public init(horizon: String, availableCents: Int, requiredCents: Int, shortfallCents: Int, weekRequiredCents: Int, nextIncomeTitle: String?, nextIncomeDate: String?, nextIncomeCents: Int?, firstRiskDate: String?) {
        self.horizon = horizon
        self.availableCents = availableCents
        self.requiredCents = requiredCents
        self.shortfallCents = shortfallCents
        self.weekRequiredCents = weekRequiredCents
        self.nextIncomeTitle = nextIncomeTitle
        self.nextIncomeDate = nextIncomeDate
        self.nextIncomeCents = nextIncomeCents
        self.firstRiskDate = firstRiskDate
    }
}

public struct FinanceSnapshot: Codable, Sendable {
    public let today: String
    public let accounts: [Account]
    public let categories: [FinanceCategory]
    public let entries: [FinanceEntry]
    public let occurrences: [FinanceEntry]
    public let rules: [RecurringRule]
    public let budgets: [Budget]
    public let liquidity: LiquidityResult?
    public let forecast: [ForecastPoint]

    public init(today: String, accounts: [Account], categories: [FinanceCategory], entries: [FinanceEntry], occurrences: [FinanceEntry], rules: [RecurringRule], budgets: [Budget], liquidity: LiquidityResult?, forecast: [ForecastPoint]) {
        self.today = today
        self.accounts = accounts
        self.categories = categories
        self.entries = entries
        self.occurrences = occurrences
        self.rules = rules
        self.budgets = budgets
        self.liquidity = liquidity
        self.forecast = forecast
    }

    public static let empty = FinanceSnapshot(today: "", accounts: [], categories: [], entries: [], occurrences: [], rules: [], budgets: [], liquidity: nil, forecast: [])
}

/// Links a CSV-import fingerprint to the entry it created, so re-importing an
/// overlapping statement is still recognised after a backup restore.
public struct BankImportRecord: Hashable, Codable, Sendable {
    public let fingerprint: String
    public let entryID: String

    public init(fingerprint: String, entryID: String) {
        self.fingerprint = fingerprint
        self.entryID = entryID
    }
}

/// Metadata of a receipt file attached to a booking. The file itself lives in
/// the `Belege` folder next to the database, named by its content hash.
public struct EntryAttachment: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let entryID: String
    public var fileName: String
    public let storedName: String
    public let sizeBytes: Int
    public let sha256: String
    public let createdAt: String

    public init(id: String = UUID().uuidString, entryID: String, fileName: String, storedName: String, sizeBytes: Int, sha256: String, createdAt: String = "") {
        self.id = id
        self.entryID = entryID
        self.fileName = fileName
        self.storedName = storedName
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.createdAt = createdAt
    }
}

public struct FinanceBackup: Codable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: String
    public let accounts: [Account]
    public let categories: [FinanceCategory]
    public let entries: [FinanceEntry]
    public let rules: [RecurringRule]
    public let budgets: [Budget]
    public let bankImportRecords: [BankImportRecord]?
    public let attachments: [EntryAttachment]?

    public init(schemaVersion: Int = 1, exportedAt: String, accounts: [Account], categories: [FinanceCategory], entries: [FinanceEntry], rules: [RecurringRule], budgets: [Budget], bankImportRecords: [BankImportRecord]? = nil, attachments: [EntryAttachment]? = nil) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.accounts = accounts
        self.categories = categories
        self.entries = entries
        self.rules = rules
        self.budgets = budgets
        self.bankImportRecords = bankImportRecords
        self.attachments = attachments
    }
}
