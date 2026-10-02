import SwiftUI
import Observation
import Security

enum AppLockError: LocalizedError {
    case wrongCurrentCode
    case invalidCode
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .wrongCurrentCode: "Der bisherige Code ist nicht korrekt."
        case .invalidCode: "Der neue Code muss mindestens vier Zeichen enthalten."
        case .keychain(let status): "Der Code konnte nicht sicher gespeichert werden (Schlüsselbund-Fehler \(status))."
        }
    }
}

@MainActor
@Observable
final class AppLockManager {
    /// Bootstrap code for a fresh installation. A custom code replaces it in
    /// Keychain and therefore survives normal app updates.
    static let defaultCode = "2026"

    private(set) var isLocked = true
    private(set) var hasCustomCode = false
    var errorMessage: String?

    private let service = "de.creativtechnik.mein-finanzplan.lock"
    private let account = "local-app-code"

    init() {
        hasCustomCode = storedCode() != nil
    }

    func unlock(with code: String) -> Bool {
        guard code == activeCode else {
            errorMessage = "Der eingegebene Code ist nicht korrekt."
            return false
        }
        errorMessage = nil
        isLocked = false
        return true
    }

    func lock() {
        isLocked = true
    }

    func changeCode(current: String, new: String, confirmation: String) throws {
        guard current == activeCode else { throw AppLockError.wrongCurrentCode }
        guard new.count >= 4, new == confirmation else { throw AppLockError.invalidCode }
        try storeCode(new)
        hasCustomCode = true
    }

    func resetToDefault(current: String) throws {
        guard current == activeCode else { throw AppLockError.wrongCurrentCode }
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppLockError.keychain(status) }
        hasCustomCode = false
    }

    private var activeCode: String { storedCode() ?? Self.defaultCode }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func storedCode() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func storeCode(_ code: String) throws {
        let data = Data(code.utf8)
        let status: OSStatus
        if storedCode() == nil {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        } else {
            status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw AppLockError.keychain(status) }
    }
}

struct AppUnlockView: View {
    @Environment(AppLockManager.self) private var appLock
    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Theme.workspace.ignoresSafeArea()
            VStack(spacing: Theme.Space.xl) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accentStrong)
                    .frame(width: 68, height: 68)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(spacing: Theme.Space.sm) {
                    Text("Mein Finanzplan").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Lokalen App-Code eingeben").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                SecureField("Code", text: $code)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Theme.Space.md)
                    .frame(width: 280, height: 44)
                    .background(Theme.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focused($isFocused)
                    .onSubmit(unlock)
                if let error = appLock.errorMessage {
                    Text(error).font(Theme.micro).foregroundStyle(Theme.paleRedText)
                }
                Button("Entsperren", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                if !appLock.hasCustomCode {
                    Text("Erster Start: Standardcode 2026")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.border) }
        }
        .onAppear { isFocused = true }
    }

    private func unlock() {
        if appLock.unlock(with: code) { code = "" }
    }
}

struct ChangeAppCodeView: View {
    @Environment(AppLockManager.self) private var appLock
    @State private var current = ""
    @State private var newCode = ""
    @State private var confirmation = ""
    @State private var message: String?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FinanceModalHeader(title: "App-Code ändern", subtitle: "Sicher im macOS-Schlüsselbund gespeichert", systemImage: "lock.rotation", onClose: onClose)
            Divider().overlay(Theme.border.opacity(0.65))
            VStack(spacing: Theme.Space.lg) {
                secureField("Bisheriger Code", text: $current)
                secureField("Neuer Code", text: $newCode)
                secureField("Neuen Code wiederholen", text: $confirmation)
                if let message { Text(message).font(Theme.caption).foregroundStyle(Theme.paleRedText) }
                Label("Der App-Code ist nicht Teil der JSON-Datensicherung und bleibt bei Updates erhalten.", systemImage: "checkmark.shield")
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Space.xl)
            Divider().overlay(Theme.border.opacity(0.65))
            HStack {
                Button("Auf 2026 zurücksetzen") { reset() }.buttonStyle(.bordered)
                Spacer()
                Button("Abbrechen", action: onClose).buttonStyle(.bordered)
                Button("Speichern", action: save).buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(newCode.count < 4 || newCode != confirmation)
            }
            .padding(Theme.Space.xl)
        }
        .frame(width: 560)
        .background(Theme.canvas)
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textFieldStyle(.roundedBorder)
    }

    private func save() {
        do { try appLock.changeCode(current: current, new: newCode, confirmation: confirmation); onClose() }
        catch { message = error.localizedDescription }
    }

    private func reset() {
        do { try appLock.resetToDefault(current: current); onClose() }
        catch { message = error.localizedDescription }
    }
}
