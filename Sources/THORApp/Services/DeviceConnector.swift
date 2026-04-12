import Foundation
import THORShared

/// Orchestrates the full device connection lifecycle:
/// SSH connect -> open tunnel -> agent health -> capabilities fetch -> persist.
@MainActor
final class DeviceConnector {
    private let appState: AppState
    private var agentClients: [Int64: AgentClient] = [:]
    private var localPorts: [Int64: Int] = [:]
    private var nextLocalPort = 18470
    private var reconnectAttempts: [Int64: Int] = [:]

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Connect

    /// Full enrollment flow for a device.
    func connect(device: Device) async throws {
        guard let deviceID = device.id else { return }

        // Update state to connecting
        await updateConnectionState(deviceID: deviceID, status: .unknown, reason: "Connecting...")

        // Step 1: Load device config
        let config = await loadDeviceConfig(for: deviceID)
        let keyPath = appState.keychain.sshKeyPath(for: deviceID)
        let (sshHost, sshPort) = resolveSSHTarget(device: device, config: config)

        // Step 2: SSH connect
        do {
            let session = try await appState.sshManager.connect(
                deviceID: deviceID,
                hostname: sshHost,
                username: config.sshUsername,
                port: sshPort,
                keyPath: keyPath
            )

            // Step 3: Open tunnel to agent API
            let localPort = nextLocalPort
            nextLocalPort += 1
            try await session.openTunnel(localPort: localPort, remotePort: config.agentPort)
            localPorts[deviceID] = localPort

            // Give tunnel a moment to establish
            try await Task.sleep(for: .seconds(1))

            // Step 4: Create agent client and check health
            let client = AgentClient(port: localPort)
            agentClients[deviceID] = client

            let health = try await client.health()
            guard health.isHealthy else {
                throw AgentClientError.agentUnhealthy(status: health.status)
            }

            // Step 5: Fetch capabilities and persist
            let caps = try await client.capabilities()
            try await persistCapabilities(deviceID: deviceID, caps: caps)

            // Step 6: Update connection state to connected
            await updateConnectionState(deviceID: deviceID, status: .connected)

        } catch {
            await updateConnectionState(
                deviceID: deviceID,
                status: classifyError(error),
                reason: error.localizedDescription
            )
            throw error
        }
    }

    /// Connect directly via agent port (no SSH tunnel — for Docker sim testing).
    func connectDirect(device: Device, agentPort: Int) async throws {
        guard let deviceID = device.id else { return }

        await updateConnectionState(deviceID: deviceID, status: .unknown, reason: "Connecting directly...")

        let client = AgentClient(port: agentPort)
        agentClients[deviceID] = client
        localPorts[deviceID] = agentPort

        do {
            let health = try await client.health()
            guard health.isHealthy else {
                throw AgentClientError.agentUnhealthy(status: health.status)
            }

            let caps = try await client.capabilities()
            try await persistCapabilities(deviceID: deviceID, caps: caps)
            await updateConnectionState(deviceID: deviceID, status: .connected)
        } catch {
            await updateConnectionState(
                deviceID: deviceID,
                status: classifyError(error),
                reason: error.localizedDescription
            )
            throw error
        }
    }

    /// Disconnect a device.
    func disconnect(deviceID: Int64) async {
        agentClients.removeValue(forKey: deviceID)
        localPorts.removeValue(forKey: deviceID)
        await appState.sshManager.disconnect(deviceID: deviceID)
        await updateConnectionState(deviceID: deviceID, status: .disconnected)
    }

    // MARK: - Agent Access

    func agentClient(for deviceID: Int64) -> AgentClient? {
        agentClients[deviceID]
    }

    /// Fetch fresh metrics from the agent.
    func fetchMetrics(for deviceID: Int64) async throws -> AgentMetricsResponse? {
        guard let client = agentClients[deviceID] else { return nil }
        return try await client.metrics()
    }

    /// Check health of a connected device.
    func checkHealth(for deviceID: Int64) async -> Bool {
        guard let client = agentClients[deviceID] else { return false }
        do {
            let health = try await client.health()
            if health.isHealthy {
                await updateConnectionState(deviceID: deviceID, status: .connected)
                return true
            } else {
                await updateConnectionState(deviceID: deviceID, status: .degraded, reason: "Agent unhealthy")
                return false
            }
        } catch {
            await updateConnectionState(
                deviceID: deviceID,
                status: .degraded,
                reason: error.localizedDescription
            )
            return false
        }
    }

    // MARK: - Health Polling

    /// Start periodic health checks for all connected devices with auto-reconnect.
    func startHealthPolling() async {
        while !Task.isCancelled {
            for (deviceID, _) in agentClients {
                let healthy = await checkHealth(for: deviceID)
                if !healthy {
                    await attemptReconnect(deviceID: deviceID)
                }
            }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    /// Attempt to reconnect a disconnected device with exponential backoff.
    private func attemptReconnect(deviceID: Int64) async {
        let config = await loadDeviceConfig(for: deviceID)
        guard config.autoReconnect else { return }

        let attempts = reconnectAttempts[deviceID] ?? 0
        guard attempts < config.reconnectMaxRetries else {
            await updateConnectionState(
                deviceID: deviceID,
                status: .disconnected,
                reason: "Max reconnect attempts (\(config.reconnectMaxRetries)) reached"
            )
            return
        }

        // Exponential backoff: 2s, 4s, 8s, 16s, 32s
        let delay = min(Double(2 << attempts), 32.0)
        try? await Task.sleep(for: .seconds(delay))

        guard let device = appState.devices.first(where: { $0.id == deviceID }) else { return }

        reconnectAttempts[deviceID] = attempts + 1
        await updateConnectionState(
            deviceID: deviceID,
            status: .unknown,
            reason: "Reconnecting (attempt \(attempts + 1)/\(config.reconnectMaxRetries))..."
        )

        do {
            // For direct connections, re-establish
            if let existingPort = localPorts[deviceID] {
                let client = AgentClient(port: existingPort)
                let health = try await client.health()
                if health.isHealthy {
                    agentClients[deviceID] = client
                    reconnectAttempts[deviceID] = 0
                    await updateConnectionState(deviceID: deviceID, status: .connected)
                    return
                }
            }

            // Full reconnect
            try await connect(device: device)
            reconnectAttempts[deviceID] = 0
        } catch {
            // Will retry on next polling cycle
        }
    }

    // MARK: - Private

    private func resolveSSHTarget(device: Device, config: DeviceConfig) -> (String, Int) {
        return (device.hostname, config.sshPort)
    }

    private func loadDeviceConfig(for deviceID: Int64) async -> DeviceConfig {
        if let db = appState.db {
            if let config = try? await db.reader.read({ dbConn in
                try DeviceConfig.filter(Column("deviceID") == deviceID).fetchOne(dbConn)
            }) {
                return config
            }
        }
        return DeviceConfig(deviceID: deviceID)
    }

    /// Save or update device config.
    func saveDeviceConfig(_ config: DeviceConfig) async throws {
        guard let db = appState.db else { return }
        try await db.writer.write { [config] dbConn in
            // Upsert
            try DeviceConfig
                .filter(Column("deviceID") == config.deviceID)
                .deleteAll(dbConn)
            let record = config
            try record.insert(dbConn)
        }
    }

    private func persistCapabilities(
        deviceID: Int64,
        caps: AgentCapabilitiesResponse
    ) async throws {
        guard let db = appState.db else { return }

        let snapshot = CompatibilitySnapshot(
            deviceID: deviceID,
            jetsonModel: caps.hardware.model,
            osRelease: caps.os.distro,
            jetpackVersion: caps.jetpackVersion,
            agentVersion: caps.agentVersion,
            dockerVersion: caps.dockerVersion,
            ros2Presence: caps.ros2Available,
            capabilitiesJSON: String(decoding: (try? JSONEncoder().encode(caps)) ?? Data(), as: UTF8.self),
            supportStatus: determineSupportStatus(model: caps.hardware.model)
        )

        try await db.writer.write { [snapshot] dbConn in
            let record = snapshot
            try record.insert(dbConn)
        }

        // Update device IP if we learned it
        try await db.writer.write { [deviceID] dbConn in
            if var device = try Device.fetchOne(dbConn, id: deviceID) {
                device.updatedAt = Date()
                try device.update(dbConn)
            }
        }

        await appState.refreshFoundationState(for: deviceID)
        appState.appendEvent("Updated capabilities for device \(deviceID)")
    }

    private func updateConnectionState(
        deviceID: Int64,
        status: ConnectionStatus,
        reason: String? = nil
    ) async {
        let state = ConnectionState(
            deviceID: deviceID,
            status: status,
            lastCheckedAt: Date(),
            lastConnectedAt: status == .connected ? Date() : nil,
            failureReason: reason,
            failureCode: status == .connected ? nil : status.rawValue
        )

        // Persist to DB
        if let db = appState.db {
            try? await db.writer.write { [state, deviceID] dbConn in
                // Upsert: delete existing then insert
                try ConnectionState
                    .filter(Column("deviceID") == deviceID)
                    .deleteAll(dbConn)
                let record = state
                try record.insert(dbConn)
            }
        }

        // Update in-memory state
        appState.connectionStates[deviceID] = state
        await appState.refreshFoundationState(for: deviceID)
    }

    private func determineSupportStatus(model: String) -> SupportStatus {
        let lower = model.lowercased()
        if lower.contains("thor") { return .supported }
        if lower.contains("orin") { return .supported }
        if lower.contains("jetson") { return .supportedWithLimits }
        return .unknown
    }

    private func classifyError(_ error: Error) -> ConnectionStatus {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("auth") || desc.contains("permission denied") {
            return .authFailed
        }
        if desc.contains("host key") {
            return .hostKeyMismatch
        }
        if desc.contains("connection refused") || desc.contains("unreachable") {
            return .unreachable
        }
        return .disconnected
    }
}
