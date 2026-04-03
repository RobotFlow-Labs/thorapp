import SwiftUI
import THORShared

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var workspace: WorkspaceSelection = .devices

    var body: some View {
        Group {
            if !onboardingComplete {
                OnboardingView(isComplete: $onboardingComplete)
            } else {
                mainSplitView
            }
        }
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

    private var mainSplitView: some View {
        NavigationSplitView {
            DeviceListView()
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        workspaceButton(.devices, label: "Devices", systemImage: "cpu")
                        workspaceButton(.fleet, label: "Fleet", systemImage: "rectangle.3.group")
                        workspaceButton(.registries, label: "Registries", systemImage: "shippingbox.circle")
                    }
                }
        } detail: {
            if workspace == .fleet {
                FleetView()
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                workspace = .devices
                            } label: {
                                Label("Back to Devices", systemImage: "chevron.left")
                            }
                        }
                    }
            } else if workspace == .registries {
                RegistryWorkspaceView()
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                workspace = .devices
                            } label: {
                                Label("Back to Devices", systemImage: "chevron.left")
                            }
                        }
                    }
            } else if let device = appState.selectedDevice {
                DeviceDetailView(device: device)
            } else {
                EmptyDeviceView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 550)
    }

    private func workspaceButton(_ target: WorkspaceSelection, label: String, systemImage: String) -> some View {
        Button {
            workspace = target
        } label: {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .foregroundStyle(workspace == target ? Color.accentColor : Color.primary)
        }
        .help(label)
    }
}

private enum WorkspaceSelection: String, Sendable {
    case devices
    case fleet
    case registries
}
