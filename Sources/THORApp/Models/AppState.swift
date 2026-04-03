import Foundation
import SwiftUI
import THORShared

/// Root application state shared across all views.
@Observable
@MainActor
final class AppState {
    var devices: [Device] = []
    var registryProfiles: [RegistryProfile] = []
    var selectedDeviceID: Int64?
    var connectionStates: [Int64: ConnectionState] = [:]
    var isLoading = false
    var onboardingComplete = false

    private(set) var db: DatabaseManager?
    let keychain = KeychainManager()
    let sshManager = SSHSessionManager()
    let registryCertificateService = RegistryCertificateService()
    let registryValidationService = RegistryValidationService()
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

        registryProfiles = try await db.reader.read { db in
            try RegistryProfile
                .order(RegistryProfile.Columns.displayName.asc)
                .fetchAll(db)
        }
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

    // MARK: - Registry Profiles

    func saveRegistryProfile(_ profile: RegistryProfile, password: String?) async throws -> RegistryProfile {
        guard let db else { return profile }

        var draft = profile
        draft.updatedAt = Date()
        if draft.id == nil {
            draft.createdAt = Date()
        }

        let saved = try await db.writer.write { [draft] dbConn -> RegistryProfile in
            var record = draft
            if let id = record.id, try RegistryProfile.fetchOne(dbConn, id: id) != nil {
                try record.update(dbConn)
                guard let updated = try RegistryProfile.fetchOne(dbConn, id: id) else {
                    return record
                }
                return updated
            } else {
                try record.insert(dbConn)
                guard let inserted = try RegistryProfile.fetchOne(dbConn, id: dbConn.lastInsertedRowID) else {
                    return record
                }
                return inserted
            }
        }

        if let profileID = saved.id, let password, !password.isEmpty {
            try keychain.storeRegistryPassword(password, for: profileID)
        }

        try await loadDevices()
        return saved
    }

    func removeRegistryProfile(_ profile: RegistryProfile) async throws {
        guard let db, let id = profile.id else { return }
        try await db.writer.write { dbConn in
            _ = try RegistryProfile.deleteOne(dbConn, id: id)
        }
        keychain.removeRegistrySecrets(for: id)
        registryCertificateService.removeManagedCertificate(at: profile.caCertificatePath)
        try await loadDevices()
    }

    func validateRegistryProfile(_ profile: RegistryProfile) async throws -> RegistryValidationReport {
        let password = profile.id.flatMap { keychain.registryPassword(for: $0) }
        let report = await registryValidationService.validate(profile: profile, password: password)

        guard let db, let id = profile.id else { return report }
        try await db.writer.write { [report, id] dbConn in
            guard var record = try RegistryProfile.fetchOne(dbConn, id: id) else { return }
            record.lastValidatedAt = Date()
            record.lastValidationStatus = report.status
            record.lastValidationMessage = report.summary
            record.updatedAt = Date()
            try record.update(dbConn)
        }
        try await loadDevices()
        return report
    }

    func clearRegistryPassword(for profileID: Int64) {
        keychain.removeRegistrySecrets(for: profileID)
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
