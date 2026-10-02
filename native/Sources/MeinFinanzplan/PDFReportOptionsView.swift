import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FinanceCore

struct PDFReportOptionsView: View {
    let snapshot: FinanceSnapshot
    let onClose: () -> Void
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var accountID = ""
    @State private var errorMessage: String?

    init(snapshot: FinanceSnapshot, onClose: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onClose = onClose
        let today = DateText.dateValue(snapshot.today)
        let calendar = Calendar.current
        let month = calendar.component(.month, from: today)
        let quarterMonth = ((month - 1) / 3) * 3 + 1
        _startDate = State(initialValue: calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: quarterMonth, day: 1)) ?? today)
        _endDate = State(initialValue: today)
    }

    var body: some View {
        VStack(spacing: 0) {
            FinanceModalHeader(title: "PDF-Bericht exportieren", subtitle: "Zeitraum und Kontobasis festlegen", systemImage: "doc.richtext", onClose: onClose)
            Divider().overlay(Theme.border.opacity(0.65))
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("SCHNELLAUSWAHL").font(Theme.micro).tracking(1.5).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: Theme.Space.sm) {
                        presetButton("Aktuelles Quartal", months: nil)
                        presetButton("Letzte 3 Monate", months: 3)
                        presetButton("Letzte 12 Monate", months: 12)
                    }
                }
                HStack(spacing: Theme.Space.lg) {
                    reportDateField("Von", selection: $startDate)
                    reportDateField("Bis", selection: $endDate)
                }
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("KONTOBASIS").font(Theme.micro).tracking(1.5).foregroundStyle(Theme.textSecondary)
                    Picker("Kontobasis", selection: $accountID) {
                        Text("Alle Konten zusammen").tag("")
                        ForEach(snapshot.accounts) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity)
                }
                Label("Der Bericht enthält Verlauf, Ist-/Planwerte sowie Einnahmen und Ausgaben nach Kategorien.", systemImage: "chart.bar.doc.horizontal")
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    .padding(Theme.Space.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(Theme.caption).foregroundStyle(Theme.paleRedText) }
                Spacer()
            }
            .padding(Theme.Space.xl)
            Divider().overlay(Theme.border.opacity(0.65))
            FinanceModalFooter(isValid: startDate <= endDate, onCancel: onClose, onSave: export, saveTitle: "PDF speichern")
        }
        .frame(width: 620, height: 520).background(Theme.canvas)
    }

    private func reportDateField(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label.uppercased()).font(Theme.micro).tracking(1.5).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.sm) {
                DatePicker(label, selection: selection, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                Text(DateText.shortWeekday(selection.wrappedValue))
                    .font(Theme.micro)
                    .foregroundStyle(Theme.accentStrong)
                    .frame(minWidth: 30)
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
            }
            .padding(.horizontal, Theme.Space.md).frame(height: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.frame(maxWidth: .infinity)
    }

    private func presetButton(_ label: String, months: Int?) -> some View {
        Button(label) {
            let today = DateText.dateValue(snapshot.today)
            let calendar = Calendar.current
            endDate = today
            if let months { startDate = calendar.date(byAdding: .month, value: -months, to: today) ?? today }
            else {
                let month = calendar.component(.month, from: today)
                startDate = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: ((month - 1) / 3) * 3 + 1, day: 1)) ?? today
            }
        }.buttonStyle(.bordered).pressable()
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Finanzbericht-\(DateText.string(startDate))-bis-\(DateText.string(endDate)).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FinanceReportGenerator.writePDF(snapshot: snapshot, startDate: DateText.string(startDate), endDate: DateText.string(endDate), accountID: accountID.isEmpty ? nil : accountID, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onClose()
        } catch { errorMessage = error.localizedDescription }
    }
}
