import SwiftUI
import THORShared

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var showingFleet = false

    var body: some View {
        Group {
            if !onboardingComplete {
                OnboardingView(isComplete: $onboardingComplete)
            } else if showingFleet {
                FleetView()
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
                    ToolbarItem(placement: .navigation) {
                        Button {
                            showingFleet.toggle()
                        } label: {
                            Label("Fleet", systemImage: "rectangle.3.group")
                        }
                        .help("Fleet Overview")
                    }
                }
        } detail: {
            if let device = appState.selectedDevice {
                DeviceDetailView(device: device)
            } else {
                EmptyDeviceView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 550)
    }
}
