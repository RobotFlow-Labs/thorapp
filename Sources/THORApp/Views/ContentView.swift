import SwiftUI
import THORShared

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            DeviceListView()
        } detail: {
            if let device = appState.selectedDevice {
                DeviceDetailView(device: device)
            } else {
                EmptyDeviceView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 500)
        .task {
            do {
                try appState.initializeDatabase()
                try await appState.loadDevices()
                appState.startHealthPolling()
            } catch {
                print("Failed to initialize: \(error)")
            }
        }
    }
}
