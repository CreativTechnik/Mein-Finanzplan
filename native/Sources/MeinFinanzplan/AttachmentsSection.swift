import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FinanceCore

/// Receipt changes collected while a booking dialog is open. They are applied
/// only when the booking is saved, so cancelling leaves no orphaned files.
struct AttachmentChanges {
    var newFiles: [URL] = []
    var removedIDs: [String] = []
}

struct FormAttachmentsSection: View {
    let existing: [EntryAttachment]
    @Binding var pendingURLs: [URL]
    @Binding var removedIDs: Set<String>
    let onOpen: (EntryAttachment) -> Void

    @State private var isTargeted = false
    @State private var message: String?

    private var visibleExisting: [EntryAttachment] { existing.filter { !removedIDs.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Belege").font(Theme.micro).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(action: choose) {
                    Label("Beleg hinzufügen", systemImage: "paperclip")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: Theme.Space.xs) {
                if visibleExisting.isEmpty && pendingURLs.isEmpty {
                    Text("PDF oder Foto hierher ziehen oder über „Beleg hinzufügen“ wählen. Die Datei wird lokal kopiert.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(visibleExisting) { attachment in
                    row(name: attachment.fileName, size: attachment.sizeBytes, isNew: false, open: { onOpen(attachment) }) {
                        removedIDs.insert(attachment.id)
                    }
                }
                ForEach(pendingURLs, id: \.self) { url in
                    row(name: url.lastPathComponent, size: fileSize(url), isNew: true, open: nil) {
                        pendingURLs.removeAll { $0 == url }
                    }
                }
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isTargeted ? Theme.accentSoft : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isTargeted ? Theme.accent : Theme.border.opacity(0.65), lineWidth: isTargeted ? 1.5 : 0.8)
            )
            .dropDestination(for: URL.self) { urls, _ in
                add(urls)
                return true
            } isTargeted: { isTargeted = $0 }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.paleRedText)
            }
        }
    }

    private func row(name: String, size: Int, isNew: Bool, open: (() -> Void)?, remove: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: name.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "photo")
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Button {
                open?()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Theme.body).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.textPrimary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(Theme.micro)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(open == nil)
            .help(open == nil ? "Wird beim Speichern hinzugefügt" : "Beleg öffnen")
            if isNew {
                StatusTag(text: "Neu", background: Theme.paleGreenBackground, foreground: Theme.paleGreenText)
            }
            TrashButton(label: "Beleg entfernen", action: remove)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Wähle Belege (PDF oder Foto, höchstens 25 MB je Datei)."
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func add(_ urls: [URL]) {
        message = nil
        for url in urls {
            do {
                try AttachmentStore.validate(url)
                if !pendingURLs.contains(url) { pendingURLs.append(url) }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
