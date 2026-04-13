import AppKit
import SwiftUI
import THORShared

@main
struct THORApp: App {
    @NSApplicationDelegateAdaptor(THORAppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    private var menuBarIcon: String {
        let hasFailure = appState.connectionStates.values.contains {
            $0.status == .authFailed || $0.status == .unreachable || $0.status == .hostKeyMismatch
        }
        let hasConnected = appState.connectionStates.values.contains { $0.status == .connected }

        if hasFailure { return "exclamationmark.triangle" }
        if hasConnected { return "cpu.fill" }
        return "cpu"
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task {
                        await appState.checkForUpdates(userInitiated: true)
                    }
                }
                .disabled(appState.updater.isCheckingForUpdates || appState.updater.isInstallingUpdate)
            }
        }

        MenuBarExtra("THOR", systemImage: menuBarIcon) {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

@MainActor
final class THORAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.ensureMainWindowVisible()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ensureMainWindowVisible()
        }
        return true
    }

    private func ensureMainWindowVisible() {
        if let existingWindow = NSApp.windows.first(where: { $0.isVisible && !$0.isMiniaturized }) {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        if let windowToRestore = NSApp.windows.first(where: { $0.isMiniaturized }) {
            windowToRestore.deminiaturize(nil)
            NSApp.activate(ignoringOtherApps: true)
            windowToRestore.makeKeyAndOrderFront(nil)
            return
        }

        guard
            let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu,
            let newWindowIndex = fileMenu.items.firstIndex(where: { $0.title == "New Window" && $0.isEnabled })
        else {
            return
        }

        fileMenu.performActionForItem(at: newWindowIndex)
        NSApp.activate(ignoringOtherApps: true)
    }
}
