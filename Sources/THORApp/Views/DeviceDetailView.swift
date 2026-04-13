import SwiftUI
import THORShared

struct DeviceDetailView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @AppStorage(THORWorkspacePreferences.showDockerToolsKey) private var showDockerTools = true
    @AppStorage(THORWorkspacePreferences.showTabGuidanceKey) private var showTabGuidanceByDefault = true
    @State private var latestSnapshot: CompatibilitySnapshot?
    @State private var metrics: AgentMetricsResponse?
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showingRebootConfirm = false
    @State private var showingExportDebug = false
    @State private var metricsTimer: Task<Void, Never>?
    @State private var lastMetricsRefresh: Date?
    @State private var collectingDiagnostics = false
    @State private var showingTabHelp = true

    private var isConnected: Bool {
        appState.connectionStatus(for: device.id ?? 0) == .connected
    }

    private var selectedTab: DetailTab {
        appState.selectedDetailTab
    }

    private var capabilityMatrix: CapabilityMatrix {
        appState.capabilityMatrix(for: device.id ?? 0)
    }

    private var deviceTabs: [DetailTab] {
        [.overview, .setup, .system, .power, .hardware, .sensors]
    }

    private var runtimeTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if showDockerTools {
            tabs.append(.docker)
        }
        tabs.append(contentsOf: [.ros2, .anima])
        return tabs
    }

    private var operationsTabs: [DetailTab] {
        [.files, .deploy, .gpu]
    }

    private var observeTabs: [DetailTab] {
        [.diagnostics, .logs, .history]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Feature sidebar — plain VStack buttons for reliable click handling
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarGroup("DEVICE", deviceTabs)
                    sidebarGroup("RUNTIME", runtimeTabs)
                    sidebarGroup("OPERATIONS", operationsTabs)
                    sidebarGroup("OBSERVE", observeTabs)
                }
                .padding(.vertical, 8)
            }
            .frame(width: 160)
            .background(Color(.controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if showingTabHelp {
                        TabHelpCard(
                            tab: selectedTab,
                            onHide: { showingTabHelp = false },
                            onHideByDefault: {
                                showTabGuidanceByDefault = false
                                showingTabHelp = false
                            }
                        )
                    }
                    featureContent
                }
                .padding(20)
            }
        }
        .navigationTitle(device.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingTabHelp.toggle()
                } label: {
                    Label(showingTabHelp ? "Hide Help" : "Show Help", systemImage: "questionmark.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if isConnected {
                    Button {
                        Task { await collectDiagnosticsArchive() }
                    } label: {
                        if collectingDiagnostics {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Collect Diagnostics", systemImage: "archivebox")
                        }
                    }
                    .disabled(collectingDiagnostics)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                TerminalToolbar(device: device)
            }
        }
        .task(id: device.id) {
            await loadSnapshot()
            if isConnected {
                await refreshMetrics()
            }
            if showTabGuidanceByDefault {
                showingTabHelp = true
            }
            if !showDockerTools, selectedTab == .docker {
                appState.selectedDetailTab = .overview
            }
        }
        .task(id: selectedTab) {
            if showTabGuidanceByDefault {
                showingTabHelp = true
            }
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
        .onChange(of: showDockerTools) { _, enabled in
            if !enabled, selectedTab == .docker {
                appState.selectedDetailTab = .overview
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

    private func sidebarGroup(_ title: String, _ items: [DetailTab]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(items, id: \.self) { tab in
                let gate = capabilityMatrix.gate(for: tab.rawValue)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.selectedDetailTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                            .frame(width: 18)
                            .foregroundStyle(selectedTab == tab ? .white : .secondary)
                        Text(tab.label)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                        if gate.state != .supported {
                            Image(systemName: gateIcon(for: gate.state))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(selectedTab == tab ? .white.opacity(0.85) : gateColor(for: gate.state))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(selectedTab == tab ? Color.accentColor : .clear)
                    .clipShape(.rect(cornerRadius: 5))
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .opacity(gate.state == .unsupported ? 0.7 : 1)
            }
        }
    }

    @ViewBuilder
    private var featureContent: some View {
        switch selectedTab {
        case .overview:
            deviceHeader
            if let errorMessage { errorBanner(errorMessage) }
            connectionCard
            ReadinessBoardView(deviceID: device.id ?? 0)
            if isConnected { metricsCard }
            capabilitiesCard
            quickActions
        case .setup:
            SetupView(device: device)
        case .system:
            gatedContent(for: .system) {
                if let id = device.id { SystemInfoView(deviceID: id) } else { notConnectedPlaceholder }
            }
        case .power:
            gatedContent(for: .power) {
                if isConnected, let id = device.id { PowerView(deviceID: id) } else { notConnectedPlaceholder }
            }
        case .hardware:
            gatedContent(for: .hardware) {
                if isConnected, let id = device.id { HardwareView(deviceID: id) } else { notConnectedPlaceholder }
            }
        case .sensors:
            gatedContent(for: .sensors) {
                if isConnected, let id = device.id { SensorsView(deviceID: id) } else { notConnectedPlaceholder }
            }
        case .docker:
            gatedContent(for: .docker) {
                if isConnected, let id = device.id { DockerView(deviceID: id) } else { notConnectedPlaceholder }
            }
        case .ros2:
            gatedContent(for: .ros2) {
                if isConnected, let id = device.id { ROS2InspectorView(deviceID: id) } else { notConnectedPlaceholder }
            }
        case .anima:
            gatedContent(for: .anima) {
                if isConnected {
                    VStack(alignment: .leading, spacing: 16) {
                        ANIMAModuleListView(device: device)
                        PipelineStatusView(device: device)
                    }
                } else { notConnectedPlaceholder }
            }
        case .files:
            gatedContent(for: .files) {
                if isConnected { FileTransferView(device: device) } else { notConnectedPlaceholder }
            }
        case .deploy:
            gatedContent(for: .deploy) {
                if isConnected { DeployView(device: device) } else { notConnectedPlaceholder }
            }
        case .gpu:
            gatedContent(for: .gpu) {
                if isConnected, let id = device.id { GPUView(deviceID: id) } else { notConnectedPlaceholder }
            }
        case .logs:
            gatedContent(for: .logs) {
                if isConnected, let id = device.id { LogStreamView(deviceID: id) } else { notConnectedPlaceholder }
            }
        case .history:
            if let id = device.id {
                VStack(alignment: .leading, spacing: 16) {
                    EventTimelineView(deviceID: id)
                    TransferHistoryView(deviceID: id)
                }
            }
        case .diagnostics:
            gatedContent(for: .diagnostics) {
                DiagnosticsView(device: device)
            }
        }
    }

    private var notConnectedPlaceholder: some View {
        let status = appState.connectionStatus(for: device.id ?? 0)
        return VStack(spacing: 16) {
            Image(systemName: recoveryIcon(for: status))
                .font(.system(size: 32))
                .foregroundStyle(recoveryColor(for: status))

            Text(recoveryTitle(for: status))
                .font(.system(size: 15, weight: .medium))
            Text(recoveryMessage(for: status))
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            HStack(spacing: 12) {
                Button("Open Setup & Doctor") {
                    appState.selectedDetailTab = .setup
                }
                .buttonStyle(.borderedProminent)

                switch status {
                case .authFailed:
                    Button("Update Credentials") {
                        appState.selectedDetailTab = .setup
                    }
                    .buttonStyle(.bordered)
                case .hostKeyMismatch:
                    Button("Review Host Key") {
                        appState.selectedDetailTab = .setup
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                case .unreachable:
                    Button("Retry Connection") {
                        Task { await connectToDevice() }
                    }
                    .buttonStyle(.bordered)
                    Button("Check Network") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.network")!)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                default:
                    Button("Connect") {
                        Task { await connectToDevice() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Copy IP") {
                    if let ip = device.lastKnownIP {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ip, forType: .string)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func recoveryIcon(for status: ConnectionStatus) -> String {
        switch status {
        case .authFailed: "lock.trianglebadge.exclamationmark"
        case .hostKeyMismatch: "exclamationmark.shield"
        case .unreachable: "wifi.slash"
        case .disconnected: "link.badge.plus"
        default: "link.badge.plus"
        }
    }

    private func recoveryColor(for status: ConnectionStatus) -> Color {
        switch status {
        case .authFailed: .red
        case .hostKeyMismatch: .orange
        case .unreachable: .red
        default: .secondary
        }
    }

    private func recoveryTitle(for status: ConnectionStatus) -> String {
        switch status {
        case .authFailed: "Authentication Failed"
        case .hostKeyMismatch: "Host Key Changed"
        case .unreachable: "Device Unreachable"
        case .disconnected: "Device Disconnected"
        default: "Not Connected"
        }
    }

    private func recoveryMessage(for status: ConnectionStatus) -> String {
        switch status {
        case .authFailed: "SSH credentials were rejected. Update your SSH key or password."
        case .hostKeyMismatch: "The device's SSH host key has changed since enrollment. This could indicate a security issue or device reprovisioning."
        case .unreachable: "Cannot reach \(device.hostname). Check that the device is powered on and on the same network."
        case .disconnected: "Connect to this device to access features."
        default: "Connect to this device to get started."
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

    private var isMetricsStale: Bool {
        guard let lastRefresh = lastMetricsRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > 30
    }

    private var metricsCard: some View {
        GroupBox(label: HStack {
            Text("System Metrics")
            Spacer()
            if isMetricsStale {
                Label("Stale", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else if let lastRefresh = lastMetricsRefresh {
                Text("Updated \(lastRefresh, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }) {
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
                let rows: [(String, String)] =
                    [
                        ("Model", snap.jetsonModel),
                        ("OS", snap.osRelease),
                        ("JetPack", snap.jetpackVersion ?? "N/A"),
                        ("Agent", snap.agentVersion),
                    ] +
                    (showDockerTools ? [("Docker", snap.dockerVersion ?? "N/A")] : []) +
                    [
                        ("ROS2", snap.ros2Presence ? "Detected" : "Not found"),
                        ("Support", snap.supportStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized),
                    ]

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { entry in
                        infoRow(entry.element.0, value: entry.element.1)
                        if entry.offset != rows.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
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
                    actionButton("Collect Diagnostics", systemImage: "archivebox", role: nil) {
                        Task { await collectDiagnosticsArchive() }
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

    @ViewBuilder
    private func gatedContent<Content: View>(
        for tab: DetailTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let gate = capabilityMatrix.gate(for: tab.rawValue)
        switch gate.state {
        case .supported:
            content()
        case .degraded:
            VStack(alignment: .leading, spacing: 16) {
                capabilityNotice(gate)
                content()
            }
        case .unsupported, .needsSetup:
            CapabilityGateView(gate: gate)
        }
    }

    private func capabilityNotice(_ gate: CapabilityGate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: gateIcon(for: gate.state))
                .foregroundStyle(gateColor(for: gate.state))
            VStack(alignment: .leading, spacing: 2) {
                Text(gate.state == .degraded ? "Available with Limits" : "Needs Attention")
                    .font(.system(size: 13, weight: .medium))
                Text(gate.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let actionLabel = gate.actionLabel {
                Button(actionLabel) {
                    appState.selectedDetailTab = .setup
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(gateColor(for: gate.state).opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
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

    private func gateIcon(for state: CapabilityState) -> String {
        switch state {
        case .supported: "checkmark.circle"
        case .degraded: "exclamationmark.triangle"
        case .unsupported: "slash.circle"
        case .needsSetup: "wrench.and.screwdriver"
        }
    }

    private func gateColor(for state: CapabilityState) -> Color {
        switch state {
        case .supported: .green
        case .degraded: .orange
        case .unsupported: .red
        case .needsSetup: .blue
        }
    }

    private func loadSnapshot() async {
        guard let deviceID = device.id else { return }
        latestSnapshot = try? await appState.latestSnapshot(for: deviceID)
    }

    private func refreshMetrics() async {
        guard let deviceID = device.id else { return }
        metrics = try? await appState.fetchMetrics(for: deviceID)
        if metrics != nil {
            lastMetricsRefresh = Date()
        }
    }

    private func connectToDevice() async {
        isConnecting = true
        errorMessage = nil
        do {
            // For Docker sims, connect directly
            if device.hostname == "localhost" || device.hostname == "127.0.0.1" {
                let port = device.displayName.contains("Orin") ? 8471 : 8470
                try await appState.connectDevice(device, directPort: port)
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

    private func collectDiagnosticsArchive() async {
        collectingDiagnostics = true
        defer { collectingDiagnostics = false }

        do {
            let archiveURL = try await appState.collectDiagnostics(for: device)
            errorMessage = nil
            NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
