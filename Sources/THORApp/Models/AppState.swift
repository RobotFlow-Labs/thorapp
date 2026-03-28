import Foundation
import SwiftUI
import THORShared

/// Root application state shared across all views.
@Observable
@MainActor
final class AppState {
    var devices: [Device] = []
    var selectedDeviceID: Int64?
    var connectionStates: [Int64: ConnectionState] = [:]
    var isLoading = false
    var onboardingComplete = false

    private(set) var db: DatabaseManager?
    let keychain = KeychainManager()
    let sshManager = SSHSessionManager()
    private(set) var connector: DeviceConnector?
    private(set) var pipelineDeployer: PipelineDeployer?
    private var healthPollingTask: Task<Void, Never>?

    var selectedDevice: Device? {
        guard let id = selectedDeviceID else { return nil }
        return devices.first { $0.id == id }
    }

    // MARK: - Database

    func initializeDatabase() throws {
        db = try DatabaseManager(path: DatabaseManager.defaultPath)
        connector = DeviceConnector(appState: self)
        pipelineDeployer = PipelineDeployer(appState: self)
    }

    // MARK: - Device CRUD

    func loadDevices() async throws {
        guard let db else { return }
        isLoading = true
        defer { isLoading = false }

        devices = try await db.reader.read { db in
            try Device.fetchAll(db)
        }

        // Load connection states
        let states = try await db.reader.read { db in
            try ConnectionState.fetchAll(db)
        }
        connectionStates = Dictionary(
            uniqueKeysWithValues: states.map { ($0.deviceID, $0) }
        )
    }

    func addDevice(_ device: Device) async throws {
        guard let db else { return }
        let savedDevice = try await db.writer.write { [device] dbConn -> Device? in
            var record = device
            try record.insert(dbConn)
            return try Device.fetchOne(dbConn, id: dbConn.lastInsertedRowID)
        }
        if let savedDevice {
            devices.append(savedDevice)
        }
    }

    func removeDevice(_ device: Device) async throws {
        guard let db, let id = device.id else { return }
        try await db.writer.write { dbConn in
            _ = try Device.deleteOne(dbConn, id: id)
        }
        keychain.removeCredentials(for: id)
        await sshManager.disconnect(deviceID: id)
        devices.removeAll { $0.id == id }
        connectionStates.removeValue(forKey: id)
        if selectedDeviceID == id {
            selectedDeviceID = nil
        }
    }

    // MARK: - Connection

    func connectionState(for deviceID: Int64) -> ConnectionState? {
        connectionStates[deviceID]
    }

    func connectionStatus(for deviceID: Int64) -> ConnectionStatus {
        connectionStates[deviceID]?.status ?? .unknown
    }

    // MARK: - Connect / Disconnect

    func connectDevice(_ device: Device, directPort: Int? = nil) async throws {
        guard let connector else { return }
        if let port = directPort {
            try await connector.connectDirect(device: device, agentPort: port)
        } else {
            try await connector.connect(device: device)
        }
    }

    func disconnectDevice(_ device: Device) async {
        guard let connector, let id = device.id else { return }
        await connector.disconnect(deviceID: id)
    }

    func startHealthPolling() {
        guard let connector else { return }
        healthPollingTask?.cancel()
        healthPollingTask = Task {
            await connector.startHealthPolling()
        }
    }

    func fetchMetrics(for deviceID: Int64) async throws -> AgentMetricsResponse? {
        guard let connector else { return nil }
        return try await connector.fetchMetrics(for: deviceID)
    }

    // MARK: - Snapshots

    func latestSnapshot(for deviceID: Int64) async throws -> CompatibilitySnapshot? {
        guard let db else { return nil }
        return try await db.reader.read { dbConn in
            try CompatibilitySnapshot
                .filter(CompatibilitySnapshot.Columns.deviceID == deviceID)
                .order(CompatibilitySnapshot.Columns.capturedAt.desc)
                .fetchOne(dbConn)
        }
    }
}
