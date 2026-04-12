import SwiftUI
import THORShared

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            deviceListSection
            Divider()
            footerSection
        }
        .frame(width: 280)
        .task {
            // Refresh device data when menu opens
            try? await appState.loadDevices()
        }
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
            Text("THOR")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(appState.devices.count) device\(appState.devices.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    private var deviceListSection: some View {
        VStack(spacing: 0) {
            if appState.devices.isEmpty {
                Text("No devices configured")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(appState.devices) { device in
                    menuDeviceRow(device)
                }
            }
        }
    }

    private func menuDeviceRow(_ device: Device) -> some View {
        let status = appState.connectionStatus(for: device.id ?? 0)
        return HStack(spacing: 8) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 6, height: 6)
            Text(device.displayName)
                .font(.system(size: 12))
            Spacer()
            Text(status.rawValue.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var footerSection: some View {
        HStack(spacing: 10) {
            Button("Open THOR") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            Button("Check Updates") {
                Task {
                    await appState.checkForUpdates(userInitiated: true)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .disabled(appState.updater.isCheckingForUpdates || appState.updater.isInstallingUpdate)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private func statusColor(for status: ConnectionStatus) -> Color {
        switch status {
        case .connected: .green
        case .degraded: .orange
        case .disconnected, .unreachable, .authFailed, .hostKeyMismatch: .red
        case .unknown: .gray
        }
    }
}
