import Testing
import Foundation
@testable import THORShared

@Suite("Multi-Device Tests")
struct MultiDeviceTests {

    @Test("Connect to both Docker sims simultaneously")
    func dualConnect() async throws {
        let thorClient = AgentClient(port: 8470)
        let orinClient = AgentClient(port: 8471)

        // Both should respond
        let thorHealth = try await thorClient.health()
        let orinHealth = try await orinClient.health()

        #expect(thorHealth.isHealthy)
        #expect(orinHealth.isHealthy)
    }

    @Test("Different capabilities from different sims")
    func differentCapabilities() async throws {
        let thorClient = AgentClient(port: 8470)
        let orinClient = AgentClient(port: 8471)

        let thorCaps = try await thorClient.capabilities()
        let orinCaps = try await orinClient.capabilities()

        #expect(thorCaps.hardware.model == "Jetson Thor")
        #expect(orinCaps.hardware.model == "Jetson Orin NX")
        #expect(thorCaps.hardware.serial != orinCaps.hardware.serial)
    }

    @Test("Metrics from both devices simultaneously")
    func dualMetrics() async throws {
        let thorClient = AgentClient(port: 8470)
        let orinClient = AgentClient(port: 8471)

        async let thorMetrics = thorClient.metrics()
        async let orinMetrics = orinClient.metrics()

        let (thor, orin) = try await (thorMetrics, orinMetrics)

        #expect(thor.cpu.percent >= 0)
        #expect(orin.cpu.percent >= 0)
        #expect(thor.memory.totalMb > 0)
        #expect(orin.memory.totalMb > 0)
    }

    @Test("ANIMA modules available on both devices")
    func dualAnimaModules() async throws {
        let thorClient = AgentClient(port: 8470)
        let orinClient = AgentClient(port: 8471)

        let thorModules = try await thorClient.animaModules()
        let orinModules = try await orinClient.animaModules()

        #expect(thorModules.count >= 3)
        #expect(orinModules.count >= 3)
        // Both should have PETRA
        #expect(thorModules.modules.contains { $0.name == "petra" })
        #expect(orinModules.modules.contains { $0.name == "petra" })
    }

    @Test("Execute command on both devices")
    func dualExec() async throws {
        let thorClient = AgentClient(port: 8470)
        let orinClient = AgentClient(port: 8471)

        let thorResult = try await thorClient.exec(command: "hostname")
        let orinResult = try await orinClient.exec(command: "hostname")

        #expect(thorResult.exitCode == 0)
        #expect(orinResult.exitCode == 0)
        #expect(thorResult.stdout.contains("thor"))
        #expect(orinResult.stdout.contains("orin"))
    }

    @Test("Device persistence round-trip with multiple devices")
    func multiDeviceDB() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)

        // Insert two devices
        var thor = Device(displayName: "Thor-01", hostname: "192.168.1.100", environment: .lab, tags: "primary")
        var orin = Device(displayName: "Orin-01", hostname: "192.168.1.101", environment: .field, tags: "secondary")

        try db.writer.write { dbConn in
            try thor.insert(dbConn)
            try orin.insert(dbConn)
        }

        let devices = try db.reader.read { dbConn in
            try Device.fetchAll(dbConn)
        }
        #expect(devices.count == 2)
        #expect(devices.map(\.displayName).contains("Thor-01"))
        #expect(devices.map(\.displayName).contains("Orin-01"))

        // Insert snapshots for each
        let thorID = devices.first { $0.displayName == "Thor-01" }!.id!
        let orinID = devices.first { $0.displayName == "Orin-01" }!.id!

        var thorSnap = CompatibilitySnapshot(
            deviceID: thorID, jetsonModel: "Jetson Thor",
            osRelease: "Ubuntu 22.04", agentVersion: "0.1.0",
            supportStatus: .supported
        )
        var orinSnap = CompatibilitySnapshot(
            deviceID: orinID, jetsonModel: "Jetson Orin NX",
            osRelease: "Ubuntu 22.04", jetpackVersion: "6.0",
            agentVersion: "0.1.0", supportStatus: .supported
        )

        try db.writer.write { dbConn in
            try thorSnap.insert(dbConn)
            try orinSnap.insert(dbConn)
        }

        let snapshots = try db.reader.read { dbConn in
            try CompatibilitySnapshot.fetchAll(dbConn)
        }
        #expect(snapshots.count == 2)
        #expect(snapshots.map(\.jetsonModel).contains("Jetson Thor"))
        #expect(snapshots.map(\.jetsonModel).contains("Jetson Orin NX"))
    }
}
