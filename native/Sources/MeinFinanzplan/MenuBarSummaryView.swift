import SwiftUI
import AppKit
import FinanceCore

struct MenuBarLabelView: View {
    let store: AppStore
    let appLock: AppLockManager
    @AppStorage("menuBarShowAmount") private var showAmount = false
    @AppStorage("menuBarHideAmounts") private var hideAmounts = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appLock.isLocked ? "lock.fill" : "eurosign.circle")
            if showAmount, !hideAmounts, !appLock.isLocked, let available = store.snapshot.liquidity?.availableCents {
                Text(Money.compactString(available)).monospacedDigit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.reloadIfDayChanged()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            store.reloadIfDayChanged()
        }
    }
}

struct MenuBarSummaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppLockManager.self) private var appLock
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarHideAmounts") private var hideAmounts = false

    private static let upcomingDays = 14
    private static let hiddenAmount = "••••"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if appLock.isLocked {
                lockedContent
            } else {
                unlockedContent
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 320)
        .background(Theme.canvas)
        .onAppear { store.reloadIfDayChanged() }
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Label("Mein Finanzplan ist gesperrt", systemImage: "lock.fill")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.textPrimary)
            Text("Öffne die App und gib deinen Code ein, um Salden und Buchungen zu sehen.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("App öffnen", action: openMainWindow)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        HStack {
            Text("Mein Finanzplan").font(Theme.sectionHeader).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                hideAmounts.toggle()
            } label: {
                Image(systemName: hideAmounts ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .help(hideAmounts ? "Beträge anzeigen" : "Beträge verbergen")
        }

        if let liquidity = store.snapshot.liquidity {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Heute frei verfügbar").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                Text(amount(liquidity.availableCents))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(liquidity.shortfallCents > 0 ? Theme.paleRedText : Theme.textPrimary)
                Text("bis \(DateText.string(liquidity.horizon))").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                if liquidity.shortfallCents > 0 {
                    StatusTag(text: "Unterdeckung \(amount(liquidity.shortfallCents))", background: Theme.paleRedBackground, foreground: Theme.paleRedText)
                }
            }
        }

        if let account = store.snapshot.accounts.first(where: \.isPrimary) ?? store.snapshot.accounts.first {
            HStack {
                Text("Kontostand \(account.name)").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(amount(account.currentBalanceCents)).font(Theme.bodyEmphasis).monospacedDigit().foregroundStyle(Theme.textPrimary)
            }
        }

        Divider().overlay(Theme.border.opacity(0.65))
        upcomingSection
        Divider().overlay(Theme.border.opacity(0.65))

        HStack {
            Button("App öffnen", action: openMainWindow)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            Spacer()
            Button("Sperren") { appLock.lock() }.buttonStyle(.bordered)
        }
    }

    private var upcomingSection: some View {
        let today = store.snapshot.today
        let items = UpcomingSummary.entries(
            in: store.occurrencesAndEntries(from: today, through: FinanceCalendar.addingDays(Self.upcomingDays, to: today)),
            today: today,
            days: Self.upcomingDays
        )
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Demnächst").font(Theme.micro).foregroundStyle(Theme.textSecondary)
            if items.isEmpty {
                Text("Keine offenen Buchungen in den nächsten \(Self.upcomingDays) Tagen.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(items) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hideAmounts ? "Buchung" : entry.title).font(Theme.body).lineLimit(1).foregroundStyle(Theme.textPrimary)
                            Text(DateText.shortDate(DateText.dateValue(entry.plannedDate))).font(Theme.micro).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: Theme.Space.sm)
                        Text(hideAmounts ? Self.hiddenAmount : EntryFormat.signedAmount(entry))
                            .font(Theme.bodyEmphasis)
                            .monospacedDigit()
                            .foregroundStyle(EntryFormat.amountColor(entry))
                    }
                }
            }
        }
    }

    private func amount(_ cents: Int) -> String {
        hideAmounts ? Self.hiddenAmount : Money.string(cents)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
