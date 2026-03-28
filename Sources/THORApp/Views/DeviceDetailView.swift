import SwiftUI
import THORShared

struct DeviceDetailView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var latestSnapshot: CompatibilitySnapshot?
    @State private var metrics: AgentMetricsResponse?
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var selectedTab = DetailTab.overview
    @State private var showingRebootConfirm = false
    @State private var showingExportDebug = false
    @State private var metricsTimer: Task<Void, Never>?

    private var isConnected: Bool {
        appState.connectionStatus(for: device.id ?? 0) == .connected
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar
            Divider()

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .overview:
                        deviceHeader
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                        connectionCard
                        if isConnected {
                            metricsCard
                        }
                        capabilitiesCard
                        quickActions
                    case .files:
                        if isConnected {
                            FileTransferView(device: device)
                        } else {
                            notConnectedPlaceholder
                        }
                    case .anima:
                        if isConnected {
                            VStack(alignment: .leading, spacing: 16) {
                                ANIMAModuleListView(device: device)
                                PipelineStatusView(device: device)
                            }
                        } else {
                            notConnectedPlaceholder
                        }
                    case .ros2:
                        if isConnected, let id = device.id {
                            ROS2InspectorView(deviceID: id)
                        } else {
                            notConnectedPlaceholder
                        }
                    case .docker:
                        if isConnected, let id = device.id {
                            DockerView(deviceID: id)
                        } else {
                            notConnectedPlaceholder
                        }
                    case .deploy:
                        if isConnected {
                            DeployView(device: device)
                        } else {
                            notConnectedPlaceholder
                        }
                    case .logs:
                        if isConnected, let id = device.id {
                            LogStreamView(deviceID: id)
                        } else {
                            notConnectedPlaceholder
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(device.displayName)
        .task(id: device.id) {
            await loadSnapshot()
            if isConnected {
                await refreshMetrics()
            }
        }
        .task(id: selectedTab) {
            // Auto-refresh metrics when overview tab is visible
            if selectedTab == .overview && isConnected {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    if selectedTab == .overview && isConnected {
                        await refreshMetrics()
                    }
                }
            }
        }
        .destructiveConfirmation(
            "Reboot Device",
            message: "This will reboot \(device.displayName). The device will be temporarily unreachable.",
            actionLabel: "Reboot",
            isPresented: $showingRebootConfirm
        ) {
            Task {
                guard let client = appState.connector?.agentClient(for: device.id ?? 0) else { return }
                _ = try? await client.reboot()
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.label, systemImage: tab.icon)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : .clear)
                        .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var notConnectedPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Connect to this device to access this feature.")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            Button("Connect") {
                Task { await connectToDevice() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
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
            Text(statusLabel(for: status))
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
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
                Divider().padding(.leading, 16)
                infoRow("Status", value: statusLabel(for: appState.connectionStatus(for: device.id ?? 0)))
            }
        }
    }

    // MARK: - Metrics Card

    private var metricsCard: some View {
        GroupBox("System Metrics") {
            if let m = metrics {
                VStack(spacing: 0) {
                    metricRow("CPU", value: String(format: "%.1f%%", m.cpu.percent), icon: "cpu")
                    Divider().padding(.leading, 16)
                    metricRow(
                        "Memory",
                        value: "\(m.memory.usedMb) / \(m.memory.totalMb) MB (\(String(format: "%.0f%%", m.memory.percent)))",
                        icon: "memorychip"
                    )
                    Divider().padding(.leading, 16)
                    metricRow(
                        "Disk",
                        value: "\(String(format: "%.1f", m.disk.usedGb)) / \(String(format: "%.1f", m.disk.totalGb)) GB",
                        icon: "internaldrive"
                    )
                    Divider().padding(.leading, 16)
                    metricRow(
                        "Load",
                        value: m.cpu.loadAvg.map { String(format: "%.2f", $0) }.joined(separator: ", "),
                        icon: "chart.bar"
                    )
                    if !m.temperatures.isEmpty {
                        Divider().padding(.leading, 16)
                        metricRow(
                            "Temperature",
                            value: m.temperatures.map { "\($0.key): \(String(format: "%.0f", $0.value))C" }.joined(separator: ", "),
                            icon: "thermometer.medium"
                        )
                    }
                }
            } else {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading metrics...")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .padding(12)
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
                Text("No capability data. Connect to the device to fetch.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .padding(12)
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        GroupBox("Quick Actions") {
            HStack(spacing: 12) {
                if isConnected {
                    actionButton("Refresh", systemImage: "arrow.clockwise", role: nil) {
                        Task { await refreshMetrics() }
                    }
                    actionButton("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                        Task { await appState.disconnectDevice(device) }
                    }
                    actionButton("Reboot", systemImage: "restart", role: .destructive) {
                        showingRebootConfirm = true
                    }
                    actionButton("Export Debug", systemImage: "square.and.arrow.up", role: nil) {
                        Task {
                            let exporter = DebugBundleExporter(appState: appState)
                            try? await exporter.export(for: device)
                        }
                    }
                } else {
                    Button {
                        Task { await connectToDevice() }
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Connect", systemImage: "link")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isConnecting)
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

    private func metricRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
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

    private func statusLabel(for status: ConnectionStatus) -> String {
        switch status {
        case .connected: "Connected"
        case .degraded: "Degraded"
        case .disconnected: "Disconnected"
        case .unreachable: "Unreachable"
        case .authFailed: "Auth Failed"
        case .hostKeyMismatch: "Host Key Mismatch"
        case .unknown: "Unknown"
        }
    }

    private func loadSnapshot() async {
        guard let deviceID = device.id else { return }
        latestSnapshot = try? await appState.latestSnapshot(for: deviceID)
    }

    private func refreshMetrics() async {
        guard let deviceID = device.id else { return }
        metrics = try? await appState.fetchMetrics(for: deviceID)
    }

    private func connectToDevice() async {
        isConnecting = true
        errorMessage = nil
        do {
            // For Docker sims, connect directly
            if device.hostname == "localhost" || device.hostname == "127.0.0.1" {
                try await appState.connectDevice(device, directPort: 8470)
            } else {
                try await appState.connectDevice(device)
            }
            await loadSnapshot()
            await refreshMetrics()
        } catch {
            errorMessage = error.localizedDescription
        }
        isConnecting = false
    }
}

// MARK: - Tab Enum

private enum DetailTab: String, CaseIterable {
    case overview
    case anima
    case files
    case deploy
    case ros2
    case docker
    case logs

    var label: String {
        switch self {
        case .overview: "Overview"
        case .anima: "ANIMA"
        case .files: "Files"
        case .deploy: "Deploy"
        case .ros2: "ROS2"
        case .docker: "Docker"
        case .logs: "Logs"
        }
    }

    var icon: String {
        switch self {
        case .overview: "cpu"
        case .anima: "brain"
        case .files: "arrow.up.doc"
        case .deploy: "play.rectangle"
        case .ros2: "point.3.connected.trianglepath.dotted"
        case .docker: "shippingbox"
        case .logs: "doc.text"
        }
    }
}
