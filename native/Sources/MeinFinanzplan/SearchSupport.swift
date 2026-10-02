import SwiftUI
import FinanceCore

struct FinanceSearchField: View {
    @Binding var text: String
    var placeholder = "Suchen"

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche löschen")
            }
        }
        .font(Theme.caption)
        .padding(.horizontal, Theme.Space.md)
        .frame(width: 260, height: 36)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.border.opacity(0.65), lineWidth: 0.8)
        }
    }
}

enum FinanceSearch {
    static func matches(
        _ entry: FinanceEntry,
        query: String,
        accountName: (String) -> String,
        categoryName: (String?) -> String
    ) -> Bool {
        matches(query, values: [
            entry.title,
            entry.note ?? "",
            accountName(entry.accountID),
            entry.transferAccountID.map(accountName) ?? "",
            categoryName(entry.categoryID),
            entry.kind.label,
            String(format: "%.2f", Double(entry.amountCents) / 100),
            Money.string(entry.amountCents)
        ])
    }

    static func matches(
        _ rule: RecurringRule,
        query: String,
        accountName: (String) -> String,
        categoryName: (String?) -> String
    ) -> Bool {
        matches(query, values: [
            rule.title,
            accountName(rule.accountID),
            rule.transferAccountID.map(accountName) ?? "",
            categoryName(rule.categoryID),
            rule.kind.label,
            String(format: "%.2f", Double(rule.amountCents) / 100),
            Money.string(rule.amountCents)
        ])
    }

    static func matches(_ query: String, values: [String]) -> Bool {
        let terms = normalized(query).split(separator: " ")
        guard !terms.isEmpty else { return true }
        let haystack = normalized(values.joined(separator: " "))
        return terms.allSatisfy { haystack.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .replacingOccurrences(of: ",", with: ".")
    }
}
