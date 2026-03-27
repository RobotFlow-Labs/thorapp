import SwiftUI
import THORShared

struct DeviceListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddDevice = false

    var body: some View {
        @Bindable var state = appState

        List(appState.devices, selection: $state.selectedDeviceID) { device in
            DeviceRowView(
                device: device,
                status: appState.connectionStatus(for: device.id ?? 0)
            )
            .tag(device.id)
        }
        .listStyle(.sidebar)
        .navigationTitle("Devices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Device", systemImage: "plus") {
                    showingAddDevice = true
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task {
                        try? await appState.loadDevices()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddDevice) {
            AddDeviceView()
        }
        .overlay {
            if appState.devices.isEmpty && !appState.isLoading {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "cpu",
                    description: Text("Add a Jetson device to get started.")
                )
            }
        }
    }
}
