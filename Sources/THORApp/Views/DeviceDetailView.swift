import SwiftUI
import THORShared

struct DeviceDetailView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var latestSnapshot: CompatibilitySnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                deviceHeader
                connectionCard
                capabilitiesCard
                quickActions
            }
            .padding(20)
        }
        .navigationTitle(device.displayName)
        .task(id: device.id) {
            await loadSnapshot()
        }
    }

    // MARK: - Header

    private var deviceHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .font(.title2)
                HStack(spacing: 8) {
                    Text(device.hostname)
                        .foregroundStyle(.secondary)
                    if let ip = device.lastKnownIP {
                        Text(ip)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 14))
            }
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        let status = appState.connectionStatus(for: device.id ?? 0)
        return HStack(spacing: 6) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 8, height: 8)
            Text(status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        GroupBox("Connection") {
            VStack(spacing: 0) {
                infoRow("Host", value: device.hostname)
                Divider().padding(.leading, 16)
                infoRow("IP", value: device.lastKnownIP ?? "Unknown")
                Divider().padding(.leading, 16)
                infoRow("Environment", value: device.environment.rawValue.capitalized)
            }
        }
    }

    // MARK: - Capabilities Card

    private var capabilitiesCard: some View {
        GroupBox("Capabilities") {
            if let snap = latestSnapshot {
                VStack(spacing: 0) {
                    infoRow("Model", value: snap.jetsonModel)
                    Divider().padding(.leading, 16)
                    infoRow("OS", value: snap.osRelease)
                    Divider().padding(.leading, 16)
                    infoRow("JetPack", value: snap.jetpackVersion ?? "N/A")
                    Divider().padding(.leading, 16)
                    infoRow("Agent", value: snap.agentVersion)
                    Divider().padding(.leading, 16)
                    infoRow("Docker", value: snap.dockerVersion ?? "N/A")
                    Divider().padding(.leading, 16)
                    infoRow("ROS2", value: snap.ros2Presence ? "Detected" : "Not found")
                    Divider().padding(.leading, 16)
                    infoRow("Support", value: snap.supportStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                }
            } else {
                Text("No capability data yet. Connect to fetch.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        GroupBox("Quick Actions") {
            HStack(spacing: 12) {
                actionButton("Connect", systemImage: "link", role: nil) {
                    // TODO: Implement connection
                }
                actionButton("Reboot", systemImage: "restart", role: .destructive) {
                    // TODO: Implement reboot
                }
                actionButton("Copy IP", systemImage: "doc.on.doc", role: nil) {
                    if let ip = device.lastKnownIP {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ip, forType: .string)
                    }
                }
                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }

    private func statusColor(for status: ConnectionStatus) -> Color {
        switch status {
        case .connected: .green
        case .degraded: .orange
        case .disconnected, .unreachable: .red
        case .authFailed, .hostKeyMismatch: .red
        case .unknown: .gray
        }
    }

    private func loadSnapshot() async {
        guard let deviceID = device.id else { return }
        latestSnapshot = try? await appState.latestSnapshot(for: deviceID)
    }
}
