import SwiftUI
import AppKit

enum Section: String, CaseIterable, Identifiable {
    case dashboard, calendar, accounts, transactions, recurrences, budgets, statistics, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: "Übersicht"
        case .calendar: "Kalender"
        case .accounts: "Konten"
        case .transactions: "Buchungen"
        case .recurrences: "Wiederkehrend"
        case .budgets: "Budgets"
        case .statistics: "Statistik"
        case .settings: "Einstellungen"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "house"
        case .calendar: "calendar"
        case .accounts: "wallet.bifold"
        case .transactions: "list.bullet.rectangle"
        case .recurrences: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .budgets: "chart.pie"
        case .statistics: "chart.xyaxis.line"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Section = .dashboard
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            navigationColumn
            VStack(spacing: 0) {
                topBar
                detail
            }
        }
        .transaction { transaction in
            // Reduced Motion: keep the same animations (opacity/state still reads clearly)
            // but run them much faster instead of cutting them entirely.
            if reduceMotion {
                transaction.animation = transaction.animation?.speed(4)
            }
        }
        .background(Theme.workspace)
        .ignoresSafeArea(.container, edges: .top)
        .tint(Theme.accent)
        .alert("Fehler", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var detail: some View {
        Group {
            switch selection {
            case .dashboard: DashboardView {
                selection = .statistics
            }
            case .calendar: CalendarView()
            case .accounts: AccountsView()
            case .transactions: TransactionsView()
            case .recurrences: RecurrencesView()
            case .budgets: BudgetsView()
            case .statistics: StatisticsView()
            case .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
    }

    private var navigationColumn: some View {
        VStack(spacing: Theme.Space.xl) {
            VStack(spacing: Theme.Space.sm) {
                ForEach(Section.allCases) { section in
                    SidebarRow(section: section, isSelected: selection == section, namespace: selectionNamespace) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.md)
            .background(Theme.accent)
            .clipShape(Capsule())
            .shadow(color: Theme.accentStrong.opacity(0.24), radius: 16, x: 0, y: 10)

            Spacer(minLength: Theme.Space.md)
        }
        .padding(.top, 58)
        .padding(.bottom, Theme.Space.xl)
        .frame(width: 104)
        .background(Theme.workspace)
    }

    private var topBar: some View {
        HStack(spacing: Theme.Space.md) {
            Text("Mein Finanzplan")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Privat. Lokal. Klar.")
                .font(Theme.micro)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.xxl)
        .frame(height: 64)
        .background(Theme.workspace)
    }
}

struct FinanceLogicGuide: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FinanceModalHeader(
                title: "So funktioniert dein Finanzplan",
                subtitle: "Die richtige Reihenfolge für verlässliche Prognosen",
                systemImage: "questionmark",
                onClose: onClose
            )
            Divider().overlay(Theme.border.opacity(0.65))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    guideStep(1, "Konten zuerst", "Trage den heutigen echten Saldo und den gewünschten Mindest-Puffer ein. Das primäre Konto bestimmt den Betrag „heute frei verfügbar“.", "wallet.bifold")
                    guideStep(2, "Regelmäßiges unter Wiederkehrend", "Miete, Gehalt oder Abos gehören hierhin. Sie erscheinen automatisch in der Vorschau; pausierte Regeln werden ignoriert.", "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    guideStep(3, "Einmaliges als Buchung", "Neue Buchungen sind standardmäßig gebucht. Stelle auf „Geplant“, wenn sie nur als Vorschau dienen soll. Einnahme addiert, Ausgabe zieht ab.", "list.bullet.rectangle")
                    guideStep(4, "Umbuchungen verbinden zwei Konten", "Wähle Quell- und Zielkonto. Der Betrag wird am selben Tag beim ersten Konto abgezogen und beim zweiten hinzugefügt.", "arrow.left.arrow.right")
                    guideStep(5, "Zeiträume und Diagramme", "Tag, Woche, Monat, Quartal, Halbjahr und Jahr folgen echten Kalendergrenzen. Mit den Pfeilen wechselst du die Periode; unter Eigener Zeitraum sind freie Grenzen möglich.", "chart.xyaxis.line")
                    guideStep(6, "Wiederkehrende Termine", "Nutze festen Tag, Datumsfenster, einen Wochentag vor dem Stichtag oder einzelne konkrete Termine. Feiertage können als Ausnahmen ergänzt werden; Betragsstufen ändern die Summe ab einem Datum.", "repeat")
                    guideStep(7, "Soll und Ist abgleichen", "Konten zeigen den berechneten Soll-Saldo. Vergleiche ihn mit dem Bankkonto und bestätige ihn als heutigen Ist-Stand; Abweichungen korrigierst du über Konto bearbeiten.", "checkmark.circle")
                    guideStep(8, "Suchen", "Listen durchsuchen Bezeichnung, Betrag, Kategorie und Konto. Auf Übersicht und Statistik gilt die Suche nur für den ausgewählten Zeitraum, einschließlich archivierter Buchungen.", "magnifyingglass")
                    guideStep(9, "CSV-Kontoauszug", "Wähle in Einstellungen eine CSV-Datei. Prüfe Titel, Art, Konto und Kategorie. Bereits vorhandene Zeilen werden erkannt und abgewählt, mögliche Duplikate (gleicher Betrag, leicht abweichendes Datum oder Text) sind gelb markiert. Eine Bankzeile kann auch als Umbuchung mit Gegenkonto markiert werden.", "tablecells")
                    guideStep(10, "Datensicherung und PDF", "JSON sichert Finanzdaten lokal; vor einem Import entsteht automatisch ein Wiederherstellungspunkt. Der PDF-Bericht wird für einen Zeitraum und wahlweise ein einzelnes Konto erzeugt.", "externaldrive")
                    guideStep(11, "Apple-Kalender", "Die optionale Synchronisierung erzeugt einen eigenen Kalender und verändert keine anderen Kalender. Bei blockiertem Zugriff hilft die Schaltfläche zu den macOS-Datenschutzeinstellungen.", "calendar.badge.clock")
                    guideStep(12, "Belege und Menüleiste", "Hänge in einer Buchung PDF- oder Foto-Belege an (bis 25 MB); sie werden lokal im Ordner „Belege“ gespeichert. Das Menüleisten-Symbol zeigt den frei verfügbaren Betrag und die nächsten Buchungen; es lässt sich in den Einstellungen anpassen.", "paperclip")
                    guideStep(13, "App-Code", "Beim ersten Start gilt 2026. Ändere den Code unter Einstellungen. Er liegt im macOS-Schlüsselbund, bleibt bei Updates erhalten und wird nicht in JSON exportiert.", "lock.shield")

                    Label("Markiere nur sichere Gehälter oder Renten als „verlässliche Einnahme“. Dieser Eingang setzt den Sicherheitszeitraum der Liquiditätsberechnung.", systemImage: "checkmark.shield")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.paleBlueText)
                        .padding(Theme.Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(Theme.Space.xl)
            }
            .financeScrollIndicatorsHidden()
            Divider().overlay(Theme.border.opacity(0.65))
            HStack {
                Spacer()
                Button("Verstanden", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .pressable()
            }
            .padding(.horizontal, Theme.Space.xl)
            .frame(height: 70)
            .background(Theme.workspace)
        }
        .frame(width: 700, height: 760)
        .background(Theme.canvas)
    }

    private func guideStep(_ number: Int, _ title: String, _ text: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accentSoft)
                Image(systemName: icon).foregroundStyle(Theme.accentStrong)
                Text("\(number)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(Theme.accent, in: Circle())
                    .offset(x: 16, y: -16)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title).font(Theme.sectionHeader)
                Text(text).font(Theme.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SidebarRow: View {
    let section: Section
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: section.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accent : Color.white.opacity(isHovering ? 1 : 0.78))
                .frame(width: 44, height: 44)
                .background {
                    if isSelected {
                        Circle().fill(Color.white).matchedGeometryEffect(id: "sidebar-selection", in: namespace)
                    } else if isHovering {
                        Circle().fill(Color.white.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(section.label)
        .accessibilityLabel(section.label)
        .onHover { hovering in withAnimation(Theme.Motion.hover) { isHovering = hovering } }
    }
}
