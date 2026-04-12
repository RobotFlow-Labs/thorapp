import SwiftUI
import THORShared

struct SetupView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var isBusy = false
    @State private var message: String?
    @State private var showingAddDevice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ReadinessBoardView(deviceID: device.id ?? 0)
            doctorChecklist
            actions
            JetsonThorQuickStartView(device: device)
            guidedFlows
        }
        .task(id: device.id) {
            if let deviceID = device.id {
                await appState.refreshFoundationState(for: deviceID)
            }
        }
        .sheet(isPresented: $showingAddDevice) {
            AddDeviceView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Setup and Connection Doctor", systemImage: "wrench.and.screwdriver")
                .font(.system(size: 16, weight: .semibold))
            Text("Classify failures, retry connection, install the agent, and see what still blocks a healthy robotics session.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("The headless AGX Thor first-boot path is embedded below so operators do not need a separate runbook window.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var doctorChecklist: some View {
        GroupBox("Connection Doctor") {
            let checks = appState.setupChecks(for: device)
            VStack(spacing: 0) {
                ForEach(checks) { check in
                    DisclosureGroup {
                        if let rawDetails = check.rawDetails, !rawDetails.isEmpty {
                            Text(rawDetails)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(color(for: check.status))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.stage)
                                    .font(.system(size: 13, weight: .medium))
                                Text(check.reason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let actionLabel = check.actionLabel {
                                Text(actionLabel)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(color(for: check.status))
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    if check.id != checks.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var actions: some View {
        GroupBox("Actions") {
            HStack(spacing: 12) {
                Button {
                    Task { await retryConnection() }
                } label: {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Retry Connection", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button("Install Agent") {
                    Task { await installAgent() }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Button("Open Device Wizard") {
                    showingAddDevice = true
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private var guidedFlows: some View {
        GroupBox("Suggested Flows") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(appState.guidedFlows) { flow in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(flow.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(flow.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if flow.id != appState.guidedFlows.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func retryConnection() async {
        isBusy = true
        defer { isBusy = false }
        do {
            if device.hostname == "localhost" || device.hostname == "127.0.0.1" {
                let port = device.displayName.contains("Orin") ? 8471 : 8470
                try await appState.connectDevice(device, directPort: port)
            } else {
                try await appState.connectDevice(device)
            }
            if let deviceID = device.id {
                await appState.refreshFoundationState(for: deviceID)
            }
            message = "Connection refreshed."
        } catch {
            message = error.localizedDescription
        }
    }

    private func installAgent() async {
        isBusy = true
        defer { isBusy = false }

        let installer = AgentInstaller(appState: appState)
        do {
            let result = try await installer.install(on: device)
            message = result.message
            if let deviceID = device.id {
                await appState.refreshFoundationState(for: deviceID)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func color(for status: ReadinessStatus) -> Color {
        switch status {
        case .ready: .green
        case .warning: .orange
        case .blocked: .red
        case .unknown: .secondary
        }
    }
}
