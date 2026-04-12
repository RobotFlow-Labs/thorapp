import SwiftUI
import THORShared

@main
struct THORApp: App {
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
