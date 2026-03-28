import SwiftUI
import THORShared

struct FleetView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedEnvironment: DeviceEnvironment?
    @State private var searchText = ""
    @State private var selectedDeviceIDs: Set<Int64> = []
    @State private var isBatchRunning = false
    @State private var batchResults: [Int64: String] = [:]

    private var filteredDevices: [Device] {
        appState.devices.filter { device in
            let matchesEnv = selectedEnvironment == nil || device.environment == selectedEnvironment
            let matchesSearch = searchText.isEmpty ||
                device.displayName.localizedCaseInsensitiveContains(searchText) ||
                device.hostname.localizedCaseInsensitiveContains(searchText) ||
                device.tags.localizedCaseInsensitiveContains(searchText)
            return matchesEnv && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            fleetHeader
            Divider()
            filterBar
            Divider()
            deviceGrid
            if !batchResults.isEmpty {
                Divider()
                batchResultsBar
            }
        }
    }

    // MARK: - Header

    private var fleetHeader: some View {
        HStack(spacing: 16) {
            Label("Fleet Overview", systemImage: "rectangle.3.group")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            healthSummary
        }
        .padding(16)
    }

    private var healthSummary: some View {
        let connected = appState.connectionStates.values.filter { $0.status == .connected }.count
        let degraded = appState.connectionStates.values.filter { $0.status == .degraded }.count
        let total = appState.devices.count

        return HStack(spacing: 12) {
            summaryBadge(count: connected, color: .green, label: "Connected")
            summaryBadge(count: degraded, color: .orange, label: "Degraded")
            summaryBadge(count: total - connected - degraded, color: .gray, label: "Offline")
        }
    }

    private func summaryBadge(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Environment filter
            HStack(spacing: 4) {
                Text("ENV:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("All") { selectedEnvironment = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(selectedEnvironment == nil ? .accentColor : .secondary)
                ForEach(DeviceEnvironment.allCases, id: \.self) { env in
                    Button(env.rawValue.capitalized) { selectedEnvironment = env }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(selectedEnvironment == env ? .accentColor : .secondary)
                }
            }

            Spacer()

            TextField("Search devices...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            // Batch actions
            if !selectedDeviceIDs.isEmpty {
                batchActionsMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var batchActionsMenu: some View {
        Menu("Batch (\(selectedDeviceIDs.count))") {
            Button("Refresh Health") {
                Task { await batchAction("health") }
            }
            Button("Disconnect All Selected") {
                Task { await batchAction("disconnect") }
            }
            Divider()
            Button("Clear Selection") {
                selectedDeviceIDs.removeAll()
            }
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
    }

    // MARK: - Device Grid

    private var deviceGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 12)
            ], spacing: 12) {
                ForEach(filteredDevices) { device in
                    fleetDeviceCard(device)
                }
            }
            .padding(16)
        }
        .overlay {
            if filteredDevices.isEmpty {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "cpu",
                    description: Text(searchText.isEmpty ? "Add devices to see them here." : "No devices match your filter.")
                )
            }
        }
    }

    private func fleetDeviceCard(_ device: Device) -> some View {
        let status = appState.connectionStatus(for: device.id ?? 0)
        let isSelected = selectedDeviceIDs.contains(device.id ?? 0)

        return VStack(alignment: .leading, spacing: 8) {
            // Top row: name + status
            HStack {
                Circle()
                    .fill(statusColor(for: status))
                    .frame(width: 8, height: 8)
                Text(device.displayName)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(device.environment.rawValue.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.secondarySystemFill))
                    .clipShape(.rect(cornerRadius: 3))
            }

            // Info row
            HStack(spacing: 8) {
                Text(device.hostname)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let ip = device.lastKnownIP, ip != device.hostname {
                    Text(ip)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            // Status + tags
            HStack {
                Text(statusLabel(for: status))
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor(for: status))
                Spacer()
                if !device.tags.isEmpty {
                    Text(device.tags)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            // Batch result
            if let result = batchResults[device.id ?? 0] {
                Text(result)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1.5)
        )
        .onTapGesture {
            if isSelected {
                selectedDeviceIDs.remove(device.id ?? 0)
            } else {
                selectedDeviceIDs.insert(device.id ?? 0)
            }
        }
    }

    // MARK: - Batch Results

    private var batchResultsBar: some View {
        HStack {
            Text("Batch results:")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") {
                batchResults.removeAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Batch Actions

    private func batchAction(_ action: String) async {
        isBatchRunning = true
        batchResults.removeAll()

        for deviceID in selectedDeviceIDs {
            switch action {
            case "health":
                let healthy = await appState.connector?.checkHealth(for: deviceID) ?? false
                batchResults[deviceID] = healthy ? "Healthy" : "Unhealthy"
            case "disconnect":
                await appState.connector?.disconnect(deviceID: deviceID)
                batchResults[deviceID] = "Disconnected"
            default:
                break
            }
        }

        isBatchRunning = false
    }

    // MARK: - Helpers

    private func statusColor(for status: ConnectionStatus) -> Color {
        switch status {
        case .connected: .green
        case .degraded: .orange
        case .disconnected, .unreachable, .authFailed, .hostKeyMismatch: .red
        case .unknown: .gray
        }
    }

    private func statusLabel(for status: ConnectionStatus) -> String {
        switch status {
        case .connected: "Connected"
        case .degraded: "Degraded"
        case .disconnected: "Disconnected"
        case .unreachable: "Unreachable"
        case .authFailed: "Auth Failed"
        case .hostKeyMismatch: "Host Key Changed"
        case .unknown: "Unknown"
        }
    }
}
