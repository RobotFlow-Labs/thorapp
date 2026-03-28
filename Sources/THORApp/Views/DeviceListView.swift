import SwiftUI
import THORShared

struct DeviceListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddDevice = false
    @State private var deviceToDelete: Device?

    var body: some View {
        @Bindable var state = appState

        List(appState.devices, selection: $state.selectedDeviceID) { device in
            DeviceRowView(
                device: device,
                status: appState.connectionStatus(for: device.id ?? 0)
            )
            .tag(device.id)
            .contextMenu {
                Button("Copy Hostname") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.hostname, forType: .string)
                }
                if let ip = device.lastKnownIP {
                    Button("Copy IP") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ip, forType: .string)
                    }
                }
                Divider()
                Button("Delete Device", role: .destructive) {
                    deviceToDelete = device
                }
            }
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
        .alert("Delete Device", isPresented: Binding(
            get: { deviceToDelete != nil },
            set: { if !$0 { deviceToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let device = deviceToDelete {
                    Task { try? await appState.removeDevice(device) }
                }
                deviceToDelete = nil
            }
            Button("Cancel", role: .cancel) { deviceToDelete = nil }
        } message: {
            Text("Remove \"\(deviceToDelete?.displayName ?? "")\" and its stored credentials? This cannot be undone.")
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
