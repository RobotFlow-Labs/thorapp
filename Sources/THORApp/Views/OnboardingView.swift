import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @Environment(AppState.self) private var appState
    @State private var prereqResults: [PrerequisiteChecker.CheckResult] = []
    @State private var simulatorBusy = false
    @State private var errorMessage: String?
    @State private var showingAddDevice = false
    @State private var showingThorQuickStart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            pathChooser
            thorQuickStartCallout
            prerequisites
            guidedFlows
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            }
            Spacer()
        }
        .padding(32)
        .frame(width: 760, height: 620)
        .task {
            let checker = PrerequisiteChecker()
            prereqResults = await checker.runAll()
        }
        .sheet(isPresented: $showingAddDevice, onDismiss: handleAddDeviceDismiss) {
            AddDeviceView()
        }
        .sheet(isPresented: $showingThorQuickStart) {
            ScrollView {
                JetsonThorQuickStartView(device: nil, showsBackButton: true)
                    .padding(24)
                    .frame(minWidth: 760)
            }
            .frame(width: 820, height: 760)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THOR v0.2 Foundation")
                .font(.system(size: 32, weight: .semibold))
            Text("Discover, connect, inspect, stream, deploy, and recover from one native macOS control plane.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var pathChooser: some View {
        HStack(spacing: 16) {
            onboardingCard(
                title: "Use Simulator",
                subtitle: "Zero-to-first-device in one click",
                detail: "Verify Docker Desktop, start the THOR sims, auto-enroll Thor and Orin, connect them, and land on a healthy overview.",
                systemImage: "shippingbox.circle",
                accent: .blue,
                buttonLabel: simulatorBusy ? "Starting…" : "Start Simulator",
                buttonRole: nil,
                disabled: simulatorBusy
            ) {
                Task { await startSimulatorFlow() }
            }

            onboardingCard(
                title: "Connect Real Jetson",
                subtitle: "Discovery, host-key trust, SSH auth, agent install",
                detail: "Use the device wizard for LAN discovery, TOFU host-key confirmation, SSH key or password auth, and direct device enrollment.",
                systemImage: "antenna.radiowaves.left.and.right",
                accent: .green,
                buttonLabel: "Open Device Wizard",
                buttonRole: nil,
                disabled: false
            ) {
                showingAddDevice = true
            }
        }
    }

    private var prerequisites: some View {
        GroupBox("Host Checks") {
            VStack(spacing: 0) {
                ForEach(prereqResults) { result in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: result.status))
                            .foregroundStyle(color(for: result.status))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(result.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)

                    if result.id != prereqResults.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var thorQuickStartCallout: some View {
        GroupBox("Jetson AGX Thor Headless First Boot") {
            VStack(alignment: .leading, spacing: 10) {
                Text("If the board is brand new, THOR now includes the Mac-side serial, USB tether, bootstrap, and JetPack bring-up flow for a no-monitor setup.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Use `thorctl quickstart` when you want the exact same operator path from Terminal.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 10) {
                    Button("Open Headless Quick Start") {
                        showingThorQuickStart = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Device Wizard") {
                        showingAddDevice = true
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private var guidedFlows: some View {
        GroupBox("Built-In Guided Flows") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(appState.guidedFlows) { flow in
                    VStack(alignment: .leading, spacing: 4) {
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

    private func onboardingCard(
        title: String,
        subtitle: String,
        detail: String,
        systemImage: String,
        accent: Color,
        buttonLabel: String,
        buttonRole: ButtonRole?,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accent)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Button(buttonLabel, role: buttonRole, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(Color(.secondarySystemFill).opacity(0.55))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func startSimulatorFlow() async {
        simulatorBusy = true
        errorMessage = nil
        do {
            _ = try await appState.enrollSimulatorDevices()
            isComplete = true
        } catch {
            errorMessage = error.localizedDescription
        }
        simulatorBusy = false
    }

    private func handleAddDeviceDismiss() {
        if !appState.devices.isEmpty {
            isComplete = true
        }
    }

    private func icon(for status: PrerequisiteChecker.CheckStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }

    private func color(for status: PrerequisiteChecker.CheckStatus) -> Color {
        switch status {
        case .pass: .green
        case .warning: .orange
        case .fail: .red
        }
    }
}
