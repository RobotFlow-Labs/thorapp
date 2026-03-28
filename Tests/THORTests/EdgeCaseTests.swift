import Testing
import Foundation
@testable import THORShared

@Suite("Edge Case Tests")
struct EdgeCaseTests {

    // MARK: - Database Edge Cases

    @Test("Empty database returns no devices")
    func emptyDB() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)
        let devices = try db.reader.read { try Device.fetchAll($0) }
        #expect(devices.isEmpty)
    }

    @Test("Device deletion cascades to related records")
    func cascadeDelete() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)

        // Insert device + identity + snapshot + job + config
        var device = Device(displayName: "Cascade Test", hostname: "test.local")
        try db.writer.write { dbConn in try device.insert(dbConn) }

        let deviceID = try db.reader.read { try Device.fetchOne($0)!.id! }

        try db.writer.write { dbConn in
            var identity = DeviceIdentity(deviceID: deviceID, hostKeyFingerprint: "SHA256:test123")
            try identity.insert(dbConn)

            var snapshot = CompatibilitySnapshot(
                deviceID: deviceID, jetsonModel: "Test", osRelease: "Ubuntu",
                agentVersion: "0.1.0"
            )
            try snapshot.insert(dbConn)

            var job = Job(deviceID: deviceID, jobType: .healthCheck, status: .success)
            try job.insert(dbConn)

            var config = DeviceConfig(deviceID: deviceID)
            try config.insert(dbConn)

            var connState = ConnectionState(deviceID: deviceID, status: .connected)
            try connState.insert(dbConn)
        }

        // Delete device
        try db.writer.write { dbConn in
            _ = try Device.deleteOne(dbConn, id: deviceID)
        }

        // All related records should be gone
        let identities = try db.reader.read { try DeviceIdentity.fetchAll($0) }
        let snapshots = try db.reader.read { try CompatibilitySnapshot.fetchAll($0) }
        let jobs = try db.reader.read { try Job.fetchAll($0) }
        let configs = try db.reader.read { try DeviceConfig.fetchAll($0) }
        let states = try db.reader.read { try ConnectionState.fetchAll($0) }

        #expect(identities.isEmpty)
        #expect(snapshots.isEmpty)
        #expect(jobs.isEmpty)
        #expect(configs.isEmpty)
        #expect(states.isEmpty)
    }

    @Test("DeviceConfig defaults are sane")
    func deviceConfigDefaults() {
        let config = DeviceConfig(deviceID: 1)
        #expect(config.sshUsername == "jetson")
        #expect(config.sshPort == 22)
        #expect(config.agentPort == 8470)
        #expect(config.autoReconnect == true)
        #expect(config.reconnectMaxRetries == 5)
        #expect(config.healthCheckIntervalSec == 15)
    }

    @Test("DeviceConfig persistence round-trip")
    func deviceConfigPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)

        var device = Device(displayName: "Config Test", hostname: "192.168.1.50")
        try db.writer.write { try device.insert($0) }
        let deviceID = try db.reader.read { try Device.fetchOne($0)!.id! }

        var config = DeviceConfig(
            deviceID: deviceID,
            sshUsername: "nvidia",
            sshPort: 2222,
            agentPort: 9090,
            autoConnect: true,
            reconnectMaxRetries: 10
        )
        try db.writer.write { try config.insert($0) }

        let fetched = try db.reader.read {
            try DeviceConfig.filter(Column("deviceID") == deviceID).fetchOne($0)
        }
        #expect(fetched?.sshUsername == "nvidia")
        #expect(fetched?.sshPort == 2222)
        #expect(fetched?.agentPort == 9090)
        #expect(fetched?.autoConnect == true)
        #expect(fetched?.reconnectMaxRetries == 10)
    }

    // MARK: - Model Edge Cases

    @Test("ConnectionStatus all cases are exhaustive")
    func connectionStatusCases() {
        let allCases = ConnectionStatus.allCases
        #expect(allCases.count == 7)
        #expect(allCases.contains(.connected))
        #expect(allCases.contains(.disconnected))
        #expect(allCases.contains(.authFailed))
        #expect(allCases.contains(.hostKeyMismatch))
    }

    @Test("JobType all cases are exhaustive")
    func jobTypeCases() {
        let allCases = JobType.allCases
        #expect(allCases.count >= 10)
        #expect(allCases.contains(.animaDeploy))
        #expect(allCases.contains(.pipelineStop))
    }

    @Test("Pipeline module names round-trip")
    func pipelineModuleNames() {
        let manifest = ANIMAModuleManifest(
            schemaVersion: "1.0", name: "test", version: "0.1.0",
            displayName: "Test", description: "", category: "test",
            containerImage: "test:latest",
            capabilities: [], inputs: [], outputs: [],
            hardwarePlatforms: [], performanceProfiles: [],
            failureMode: nil, timeoutMs: nil, healthTopic: nil
        )
        let pipeline = Pipeline(
            name: "test-pipe", modules: [manifest], composeYAML: ""
        )
        #expect(pipeline.moduleNames == ["test"])
    }

    @Test("PipelineStatus all cases")
    func pipelineStatusCases() {
        let allCases = PipelineStatus.allCases
        #expect(allCases.contains(.draft))
        #expect(allCases.contains(.deploying))
        #expect(allCases.contains(.running))
        #expect(allCases.contains(.stopped))
        #expect(allCases.contains(.failed))
        #expect(allCases.contains(.degraded))
    }

    // MARK: - ANIMA Module Edge Cases

    @Test("Module with no Jetson support reports incompatible")
    func noJetsonSupport() {
        let module = ANIMAModuleManifest(
            schemaVersion: "1.0", name: "cpu-only", version: "1.0",
            displayName: "CPU Only", description: "", category: "test",
            containerImage: "test:latest",
            capabilities: [ModuleCapability(type: "compute", subtype: nil)],
            inputs: [], outputs: [],
            hardwarePlatforms: [PlatformSupport(name: "linux_x86", backends: ["cpu"])],
            performanceProfiles: [],
            failureMode: nil, timeoutMs: nil, healthTopic: nil
        )
        #expect(!module.supportsJetson(.thor))
        #expect(!module.supportsJetson(.orinNX))
        #expect(module.preferredBackend(for: .thor) == "cpu")
    }

    @Test("JetPack compatibility rejects old versions")
    func oldJetPackRejected() {
        let module = ANIMAModuleManifest(
            schemaVersion: "1.0", name: "modern", version: "1.0",
            displayName: "Modern", description: "", category: "test",
            containerImage: "test:latest",
            capabilities: [],
            inputs: [], outputs: [],
            hardwarePlatforms: [PlatformSupport(name: "jetson", backends: ["tensorrt"])],
            performanceProfiles: [],
            failureMode: nil, timeoutMs: nil, healthTopic: nil
        )
        let result = JetPackCompatibility.check(module: module, jetpackVersion: "4.6", gpuMemoryMB: 8192)
        #expect(!result.isCompatible)
    }

    @Test("JetPack compatibility accepts supported versions")
    func supportedJetPackAccepted() {
        let module = ANIMAModuleManifest(
            schemaVersion: "1.0", name: "modern", version: "1.0",
            displayName: "Modern", description: "", category: "test",
            containerImage: "test:latest",
            capabilities: [],
            inputs: [], outputs: [],
            hardwarePlatforms: [PlatformSupport(name: "jetson", backends: ["tensorrt"])],
            performanceProfiles: [],
            failureMode: nil, timeoutMs: nil, healthTopic: nil
        )
        let result = JetPackCompatibility.check(module: module, jetpackVersion: "6.1", gpuMemoryMB: 8192)
        #expect(result.isCompatible)
    }

    // MARK: - AgentClient Edge Cases

    @Test("AgentClient to nonexistent port throws")
    func agentClientBadPort() async {
        let client = AgentClient(port: 19999)
        do {
            _ = try await client.health()
            Issue.record("Should have thrown")
        } catch {
            // Expected
            #expect(true)
        }
    }

    @Test("Exec with dangerous command is blocked by agent")
    func dangerousCommandBlocked() async throws {
        let client = AgentClient(port: 8470)
        do {
            _ = try await client.exec(command: "rm -rf /")
            Issue.record("Should have been blocked")
        } catch let error as AgentClientError {
            if case .httpError(let code, _) = error {
                #expect(code == 403)
            }
        }
    }
}
