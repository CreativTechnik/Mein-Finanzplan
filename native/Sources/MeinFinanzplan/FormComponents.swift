import SwiftUI
import FinanceCore

struct FinanceModalHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            IconBadge(systemName: systemImage)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.controlSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .pressable()
            .accessibilityLabel("Schließen")
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: 82)
        .background(Theme.workspace)
    }
}

struct FinanceModalFooter: View {
    let isValid: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    var saveTitle: String = "Speichern"

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Spacer()
            Button("Abbrechen", role: .cancel, action: onCancel)
                .buttonStyle(.plain)
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Space.lg)
                .frame(height: 42)
                .pressable()
            Button(action: onSave) {
                HStack(spacing: Theme.Space.sm) {
                    Text(saveTitle)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.16), in: Circle())
                }
                .font(Theme.bodyEmphasis)
                .foregroundStyle(.white)
                .padding(.leading, Theme.Space.lg)
                .padding(.trailing, Theme.Space.sm)
                .frame(height: 42)
                .background(isValid ? Theme.accent : Theme.border)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
            .pressable()
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: 72)
        .background(Theme.workspace)
    }
}

struct FormTextInput: View {
    let label: String
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: icon).foregroundStyle(Theme.textSecondary).frame(width: 18)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.body)
            }
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.65), lineWidth: 0.8)
            )
        }
    }
}

struct FormMenuInput<Option: Hashable>: View {
    let label: String
    let icon: String
    @Binding var selection: Option
    let options: [(Option, String)]

    private var currentLabel: String {
        options.first { $0.0 == selection }?.1 ?? "Auswählen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
            Menu {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        selection = option.0
                    } label: {
                        if selection == option.0 {
                            Label(option.1, systemImage: "checkmark")
                        } else {
                            Text(option.1)
                        }
                    }
                }
            } label: {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: icon).foregroundStyle(Theme.textSecondary).frame(width: 18)
                    Text(currentLabel).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, Theme.Space.md)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.65), lineWidth: 0.8)
            )
        }
        .frame(maxWidth: .infinity)
    }
}

struct FormDateInput: View {
    let label: String
    let icon: String
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label).font(Theme.micro).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: icon).foregroundStyle(Theme.textSecondary).frame(width: 18)
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(DateText.shortWeekday(date))
                    .font(Theme.micro)
                    .foregroundStyle(Theme.accentStrong)
                    .frame(minWidth: 30)
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
            }
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 44)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.65), lineWidth: 0.8)
            )
        }
        .frame(maxWidth: .infinity)
    }
}

struct EntryKindTabs: View {
    @Binding var selection: EntryKind

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("BUCHUNGSART")
                .font(Theme.micro)
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.xs) {
                ForEach(EntryKind.allCases, id: \.self) { kind in
                    Button {
                        selection = kind
                    } label: {
                        Label(kind.label, systemImage: icon(kind))
                            .font(Theme.bodyEmphasis)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .foregroundStyle(selection == kind ? Color.white : Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(selection == kind ? Theme.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pressable()
                }
            }
            .padding(5)
            .background(Theme.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private func icon(_ kind: EntryKind) -> String {
        switch kind {
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        case .transfer: "arrow.left.arrow.right"
        }
    }
}

struct FormMoneyInput: View {
    let label: String
    @Binding var amount: String
    var kind: EntryKind = .expense

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label.uppercased()).font(Theme.micro).tracking(1.5).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                Text(kind == .expense ? "−" : kind == .income ? "+" : "↔")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(color)
                TextField("0,00", text: $amount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                Text("€")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Space.lg)
            .frame(height: 66)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private var color: Color {
        switch kind {
        case .income: Theme.chartIncome
        case .expense: Theme.chartExpense
        case .transfer: Theme.chartTransfer
        }
    }
}

/// Shared calendar-period navigation used by both the dashboard chart and the
/// statistics view, so "Quartal", "6 Monate" and "Jahr" always mean the same
/// real calendar range with the same navigation everywhere.
struct CalendarPeriodBar: View {
    @Binding var period: CalendarPeriod
    let today: String
    var kinds: [CalendarPeriodKind] = [.day, .week, .month, .quarter, .halfYear, .year, .custom]

    @State private var isPresentingCustomRange = false
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var customRangeError: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.md) {
                periodKindTabs
                periodNavigation
            }
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ScrollView(.horizontal) { periodKindTabs }
                    .financeScrollIndicatorsHidden()
                periodNavigation
            }
        }
        .popover(isPresented: $isPresentingCustomRange) { customRangeEditor }
    }

    private var periodKindTabs: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(kinds) { kind in
                Button {
                    selectKind(kind)
                } label: {
                    Text(kind.label)
                        .font(Theme.micro)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(period.kind == kind ? Color.white : Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 30)
                        .background(period.kind == kind ? Theme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .pressable()
            }
        }
        .padding(3)
        .background(Theme.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var periodNavigation: some View {
        HStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Button { period = CalendarPeriodEngine.previous(period) } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Vorherige Periode")
                Text(period.label)
                    .font(Theme.bodyEmphasis)
                    .monospacedDigit()
                    .frame(minWidth: 150)
                Button { period = CalendarPeriodEngine.next(period) } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Nächste Periode")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentStrong)
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 36)
            .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            if !containsToday {
                Button("Heute") {
                    period = CalendarPeriodEngine.period(kind: period.kind == .custom ? .month : period.kind, containing: today)
                }
                .buttonStyle(.plain)
                .font(Theme.micro)
                .foregroundStyle(Theme.accent)
                .pressable()
            }
        }
    }

    private var containsToday: Bool { period.startDate <= today && today <= period.endDate }

    private func selectKind(_ kind: CalendarPeriodKind) {
        if kind == .custom {
            customStart = DateText.dateValue(period.startDate)
            customEnd = DateText.dateValue(period.endDate)
            customRangeError = nil
            isPresentingCustomRange = true
        } else {
            period = CalendarPeriodEngine.period(kind: kind, containing: period.startDate)
        }
    }

    private var customRangeEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Freier Zeitraum").font(Theme.sectionHeader)
            FormDateInput(label: "Von", icon: "calendar", date: $customStart)
            FormDateInput(label: "Bis", icon: "calendar", date: $customEnd)
            if let customRangeError {
                Label(customRangeError, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.paleRedText)
            }
            HStack {
                Spacer()
                Button("Übernehmen") {
                    do {
                        period = try CalendarPeriodEngine.custom(start: DateText.string(customStart), end: DateText.string(customEnd))
                        isPresentingCustomRange = false
                    } catch {
                        customRangeError = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .pressable()
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 320)
    }
}

struct TrashButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.paleRedText)
                .frame(width: 30, height: 30)
                .background(Theme.paleRedBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .pressable()
        .help(label)
        .accessibilityLabel(label)
    }
}

struct FormToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title).font(Theme.bodyEmphasis).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .padding(Theme.Space.md)
        .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
