import SwiftUI
import AppKit

@main
struct MeinFinanzplanApp: App {
    @State private var store = AppStore()
    @State private var appLock = AppLockManager()
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "dark": .dark
        case "system": nil
        default: .light
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if appLock.isLocked {
                    AppUnlockView()
                } else {
                    ContentView()
                }
            }
                .environment(store)
                .environment(appLock)
                .preferredColorScheme(preferredScheme)
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear {
                    updateDockIcon()
                    Task { await store.resumeAppleCalendarSync() }
                }
                .onChange(of: appearance) { _, _ in updateDockIcon() }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { await store.resumeAppleCalendarSync() }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarSummaryView()
                .environment(store)
                .environment(appLock)
                .preferredColorScheme(preferredScheme)
        } label: {
            MenuBarLabelView(store: store, appLock: appLock)
        }
        .menuBarExtraStyle(.window)
    }

    private func updateDockIcon() {
        let isDark: Bool
        if appearance == "dark" { isDark = true }
        else if appearance == "light" { isDark = false }
        else { isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
        let name = isDark ? "AppIcon-Dark" : "AppIcon"
        if let url = Bundle.main.url(forResource: name, withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }
}
