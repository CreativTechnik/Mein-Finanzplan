import Foundation

public struct ParsedBankRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var date: String
    public var title: String
    public var signedAmountCents: Int
    public let fingerprint: String

    public init(id: UUID = UUID(), date: String, title: String, signedAmountCents: Int, fingerprint: String? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.signedAmountCents = signedAmountCents
        self.fingerprint = fingerprint ?? BankCSVParser.fingerprint(for: "\(date)|\(signedAmountCents)|\(title)")
    }
}

public enum BankCSVError: Error, LocalizedError {
    case unreadable
    case missingColumns
    case noTransactions

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Die CSV-Datei konnte nicht als Text gelesen werden."
        case .missingColumns: "Datums- oder Betragsspalte wurde nicht erkannt. Unterstützt werden typische deutsche Bankexporte."
        case .noTransactions: "Die CSV-Datei enthält keine lesbaren Buchungen."
        }
    }
}

public enum BankCSVParser {
    public static func parse(data: Data) throws -> [ParsedBankRow] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw BankCSVError.unreadable
        }
        return try parse(text: text)
    }

    public static func parse(text: String) throws -> [ParsedBankRow] {
        let delimiter = detectedDelimiter(in: text)
        let records = records(in: text, delimiter: delimiter).filter { $0.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
        guard let headerOffset = records.firstIndex(where: { row in
            row.contains(where: { isDateHeader(normalize($0)) }) && row.contains(where: { isAmountHeader(normalize($0)) || isDebitHeader(normalize($0)) || isCreditHeader(normalize($0)) })
        }) else { throw BankCSVError.missingColumns }

        let header = records[headerOffset].map(normalize)
        let dateIndex = header.firstIndex(where: isDateHeader)
        let amountIndex = header.firstIndex(where: isAmountHeader)
        let debitIndex = header.firstIndex(where: isDebitHeader)
        let creditIndex = header.firstIndex(where: isCreditHeader)
        let titleIndices = header.indices.filter { isTitleHeader(header[$0]) }
        guard let dateIndex, amountIndex != nil || debitIndex != nil || creditIndex != nil else { throw BankCSVError.missingColumns }

        var parsed: [ParsedBankRow] = []
        for row in records.dropFirst(headerOffset + 1) {
            guard row.indices.contains(dateIndex), let date = normalizedDate(row[dateIndex]) else { continue }
            let signedAmount: Int?
            if let amountIndex, row.indices.contains(amountIndex) {
                signedAmount = cents(row[amountIndex])
            } else {
                let debit = debitIndex.flatMap { row.indices.contains($0) ? cents(row[$0]) : nil }.map { -abs($0) }
                let credit = creditIndex.flatMap { row.indices.contains($0) ? cents(row[$0]) : nil }.map(abs)
                signedAmount = credit ?? debit
            }
            guard let signedAmount, signedAmount != 0 else { continue }
            let title = titleIndices.compactMap { row.indices.contains($0) ? cleaned(row[$0]) : nil }
                .filter { !$0.isEmpty }
                .uniqued()
                .joined(separator: " · ")
            parsed.append(ParsedBankRow(date: date, title: suggestedTitle(from: title), signedAmountCents: signedAmount, fingerprint: fingerprint(for: "\(date)|\(signedAmount)|\(title)")))
        }
        guard !parsed.isEmpty else { throw BankCSVError.noTransactions }
        // Identical rows within one file (two coffees, same day) are legitimate;
        // only the first keeps the plain fingerprint so older import records match.
        var occurrences: [String: Int] = [:]
        return parsed.map { row in
            let count = occurrences[row.fingerprint, default: 0] + 1
            occurrences[row.fingerprint] = count
            guard count > 1 else { return row }
            return ParsedBankRow(id: row.id, date: row.date, title: row.title, signedAmountCents: row.signedAmountCents, fingerprint: "\(row.fingerprint)#\(count)")
        }
    }

    private static func detectedDelimiter(in text: String) -> Character {
        let sample = text.split(whereSeparator: \.isNewline).prefix(8).joined(separator: "\n")
        return [";", ",", "\t"].max { left, right in sample.filter { $0 == Character(left) }.count < sample.filter { $0 == Character(right) }.count }.map(Character.init) ?? ";"
    }

    private static func records(in text: String, delimiter: Character) -> [[String]] {
        var result: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if character == delimiter, !quoted {
                row.append(field); field = ""
            } else if character == "\n", !quoted {
                row.append(field); result.append(row); row = []; field = ""
            } else { field.append(character) }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); result.append(row) }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
    }

    private static func isDateHeader(_ value: String) -> Bool { ["buchungstag", "buchungsdatum", "wertstellung", "valutadatum", "datum", "date"].contains(value) }
    private static func isAmountHeader(_ value: String) -> Bool { ["betrag", "betrag(€)", "betrag(eur)", "amount", "umsatz"].contains(value) || value.hasPrefix("betrag") }
    private static func isDebitHeader(_ value: String) -> Bool { value.contains("soll") || value.contains("belastung") || value == "debit" }
    private static func isCreditHeader(_ value: String) -> Bool { value.contains("haben") || value.contains("gutschrift") || value == "credit" }
    private static func isTitleHeader(_ value: String) -> Bool {
        ["verwendungszweck", "buchungstext", "vorgang/verwendungszweck", "beguenstigter/zahlungspflichtiger", "empfaenger", "auftraggeber", "beschreibung", "name", "purpose"].contains(value)
            || value.contains("verwendungszweck") || value.contains("zahlungspflichtiger")
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "  ", with: " ")
    }

    /// Produces a readable local title while discarding common SEPA transport
    /// metadata. The source CSV remains untouched and the proposal stays
    /// editable in the import review.
    public static func suggestedTitle(from rawValue: String, maximumLength: Int = 72) -> String {
        let labels = ["IBAN", "BIC", "EREF", "MREF", "CRED", "SVWZ", "END-TO-END", "ENDTOEND", "MANDATSREFERENZ", "GLAEUBIGER-ID"]
        let separators = CharacterSet(charactersIn: " ·|\n\t")
        let pieces = rawValue.components(separatedBy: separators)
        var kept: [String] = []
        var skipNext = false
        for rawPiece in pieces {
            let piece = rawPiece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            let upper = piece.uppercased()
            if skipNext { skipNext = false; continue }
            if labels.contains(where: { upper == $0 || upper.hasPrefix("\($0):") || upper.hasPrefix("\($0)+") }) {
                if labels.contains(upper) { skipNext = true }
                continue
            }
            let compact = piece.filter(\.isLetter).count + piece.filter(\.isNumber).count
            let isOpaqueCode = piece.count >= 18 && compact >= piece.count - 2
                && (piece.filter(\.isNumber).count >= 8 || piece.contains("-") || piece.contains("/"))
            if isOpaqueCode { continue }
            kept.append(piece)
        }
        let normalized = kept.joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "Bankbuchung" }
        guard normalized.count > maximumLength else { return normalized }
        let prefix = normalized.prefix(maximumLength + 1)
        if let boundary = prefix.lastIndex(of: " ") {
            return String(prefix[..<boundary])
        }
        return String(normalized.prefix(maximumLength))
    }

    public static func fingerprint(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func cents(_ value: String) -> Int? {
        var cleaned = cleaned(value).replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive).replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        if cleaned.contains(",") { cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        let negativeByParentheses = cleaned.hasPrefix("(") && cleaned.hasSuffix(")")
        cleaned = cleaned.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        guard let amount = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var value = amount * 100
        if negativeByParentheses { value *= -1 }
        return NSDecimalNumber(decimal: value).intValue
    }

    private static func normalizedDate(_ value: String) -> String? {
        let input = cleaned(value)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for pattern in ["dd.MM.yyyy", "d.M.yyyy", "yyyy-MM-dd", "dd.MM.yy", "MM/dd/yyyy"] {
            formatter.dateFormat = pattern
            formatter.isLenient = false
            if let date = formatter.date(from: input) {
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: date)
            }
        }
        return nil
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
