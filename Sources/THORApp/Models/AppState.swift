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
    var activeWorkspace: WorkspaceSelection = .devices
    var selectedDetailTab: DetailTab = .overview
    var cameraStudioTargetDeviceID: Int64?
    var connectionStates: [Int64: ConnectionState] = [:]
    var capabilityMatrices: [Int64: CapabilityMatrix] = [:]
    var readinessReports: [Int64: ReadinessReport] = [:]
    var recentEvents: [String] = []
    var isLoading = false
    var onboardingComplete = false

    let updater = AppUpdater()
    private(set) var db: DatabaseManager?
    let cameraBridgeService = CameraBridgeService()
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

        await refreshAllFoundationState()
    }

    func addDevice(_ device: Device) async throws {
        guard let db else { return }
        let savedDevice = try await db.writer.write { [device] dbConn -> Device? in
            let record = device
            try record.insert(dbConn)
            return try Device.fetchOne(dbConn, id: dbConn.lastInsertedRowID)
        }
        if let savedDevice {
            devices.append(savedDevice)
            if let deviceID = savedDevice.id {
                await refreshFoundationState(for: deviceID)
            }
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
            let record = draft
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

    func registryDeviceStatus(_ profile: RegistryProfile, on deviceID: Int64) async throws -> DeviceRegistryStateResponse {
        let client = try registryDeviceClient(for: deviceID)
        return try await client.deviceRegistryStatus(
            registryAddress: profile.registryAddress,
            scheme: profile.scheme
        )
    }

    func applyRegistryProfile(_ profile: RegistryProfile, to deviceID: Int64) async throws -> DeviceRegistryApplyResponse {
        let client = try registryDeviceClient(for: deviceID)
        let certificateData = try registryCertificateData(for: profile)
        let password = profile.id.flatMap { keychain.registryPassword(for: $0) }
        return try await client.applyRegistry(
            registryAddress: profile.registryAddress,
            scheme: profile.scheme,
            caCertificatePEM: certificateData.flatMap { String(data: $0, encoding: .utf8) },
            caCertificateBase64: certificateData?.base64EncodedString(),
            username: profile.username,
            password: password
        )
    }

    func validateRegistryProfile(
        _ profile: RegistryProfile,
        on deviceID: Int64,
        image: String? = nil
    ) async throws -> DeviceRegistryValidationResponse {
        let client = try registryDeviceClient(for: deviceID)
        return try await client.validateDeviceRegistry(
            registryAddress: profile.registryAddress,
            scheme: profile.scheme,
            image: image
        )
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

    func openCameraStudio(for deviceID: Int64? = nil) {
        if let deviceID {
            selectedDeviceID = deviceID
            cameraStudioTargetDeviceID = deviceID
        }
        activeWorkspace = .studio
    }

    func showDeviceHardware(deviceID: Int64? = nil) {
        if let deviceID {
            selectedDeviceID = deviceID
        }
        selectedDetailTab = .hardware
        activeWorkspace = .devices
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

    func appendEvent(_ message: String) {
        recentEvents.insert("[\(ISO8601DateFormatter().string(from: Date()))] \(message)", at: 0)
        recentEvents = Array(recentEvents.prefix(100))
    }

    // MARK: - Updates

    func checkForUpdatesOnLaunch() async {
        await updater.checkForUpdatesOnLaunch()
    }

    func checkForUpdates(userInitiated: Bool) async {
        await updater.checkForUpdates(userInitiated: userInitiated)
    }

    func installAvailableUpdate() async {
        await updater.installAvailableUpdate()
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

    func deviceConfig(for deviceID: Int64) async -> DeviceConfig {
        guard let db else { return DeviceConfig(deviceID: deviceID) }
        return (try? await db.reader.read { dbConn in
            try DeviceConfig
                .filter(Column("deviceID") == deviceID)
                .fetchOne(dbConn)
        }) ?? DeviceConfig(deviceID: deviceID)
    }

    private func registryDeviceClient(for deviceID: Int64) throws -> AgentClient {
        guard let client = connector?.agentClient(for: deviceID) else {
            throw RegistryDeviceIntegrationError.deviceNotConnected
        }
        return client
    }

    private func registryCertificateData(for profile: RegistryProfile) throws -> Data? {
        guard let path = profile.caCertificatePath else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RegistryDeviceIntegrationError.certificateMissing
        }
        return try Data(contentsOf: url)
    }
}

enum RegistryDeviceIntegrationError: Error, LocalizedError {
    case deviceNotConnected
    case certificateMissing

    var errorDescription: String? {
        switch self {
        case .deviceNotConnected:
            return "Device is not connected. Connect the Jetson before applying registry settings."
        case .certificateMissing:
            return "The registry certificate file is missing. Re-import it before applying to a device."
        }
    }
}
