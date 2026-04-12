import Testing
import Foundation
import GRDB
@testable import THORShared

@Suite("Database Tests")
struct DatabaseTests {
    @Test("Database initializes and creates tables")
    func databaseInit() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("test.sqlite").path
        let db = try DatabaseManager(path: dbPath)

        // Verify we can write and read a device
        var device = Device(
            displayName: "Test Jetson",
            hostname: "192.168.1.100",
            environment: .lab
        )

        try db.writer.write { dbConn in
            try device.insert(dbConn)
        }

        let fetched = try db.reader.read { dbConn in
            try Device.fetchAll(dbConn)
        }

        #expect(fetched.count == 1)
        #expect(fetched[0].displayName == "Test Jetson")
        #expect(fetched[0].hostname == "192.168.1.100")
        #expect(fetched[0].environment == .lab)
    }

    @Test("Device CRUD operations")
    func deviceCRUD() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("test.sqlite").path
        let db = try DatabaseManager(path: dbPath)

        // Insert
        var device = Device(
            displayName: "Thor-01",
            hostname: "jetson-thor.local",
            lastKnownIP: "10.0.0.50",
            environment: .field,
            tags: "robot,primary"
        )
        try db.writer.write { dbConn in
            try device.insert(dbConn)
        }

        // Read
        let devices = try db.reader.read { dbConn in
            try Device.fetchAll(dbConn)
        }
        #expect(devices.count == 1)
        let saved = devices[0]
        #expect(saved.id != nil)
        #expect(saved.tags == "robot,primary")

        // Update
        try db.writer.write { dbConn in
            var updated = saved
            updated.displayName = "Thor-01-Updated"
            try updated.update(dbConn)
        }

        let afterUpdate = try db.reader.read { dbConn in
            try Device.fetchOne(dbConn, id: saved.id!)
        }
        #expect(afterUpdate?.displayName == "Thor-01-Updated")

        // Delete
        try db.writer.write { dbConn in
            _ = try Device.deleteOne(dbConn, id: saved.id!)
        }

        let afterDelete = try db.reader.read { dbConn in
            try Device.fetchAll(dbConn)
        }
        #expect(afterDelete.isEmpty)
    }

    @Test("Job lifecycle states")
    func jobLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("test.sqlite").path
        let db = try DatabaseManager(path: dbPath)

        // Create device first
        var device = Device(displayName: "Test", hostname: "test.local")
        try db.writer.write { dbConn in
            try device.insert(dbConn)
        }

        let deviceID = try db.reader.read { dbConn in
            try Device.fetchOne(dbConn)!.id!
        }

        // Create job
        var job = Job(
            deviceID: deviceID,
            jobType: .enroll,
            status: .created
        )
        try db.writer.write { dbConn in
            try job.insert(dbConn)
        }

        // Transition to running
        try db.writer.write { dbConn in
            var running = try Job.fetchOne(dbConn)!
            running.status = .running
            running.startedAt = Date()
            try running.update(dbConn)
        }

        // Transition to success
        try db.writer.write { dbConn in
            var done = try Job.fetchOne(dbConn)!
            done.status = .success
            done.finishedAt = Date()
            try done.update(dbConn)
        }

        let final = try db.reader.read { dbConn in
            try Job.fetchOne(dbConn)!
        }
        #expect(final.status == .success)
        #expect(final.startedAt != nil)
        #expect(final.finishedAt != nil)
    }

    @Test("v0.2 foundation tables are created")
    func v0_2FoundationTablesExist() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("test.sqlite").path
        let db = try DatabaseManager(path: dbPath)

        let tableCount = try db.reader.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*)
                    FROM sqlite_master
                    WHERE type = 'table'
                      AND name IN (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "launch_profiles",
                    "deploy_recipes",
                    "recipe_runs",
                    "diagnostic_runs",
                    "guided_flow_progress",
                ]
            ) ?? 0
        }

        #expect(tableCount == 5)
    }

    @Test("v0.2 foundation records persist and round-trip")
    func v0_2FoundationRecordsRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("test.sqlite").path
        let db = try DatabaseManager(path: dbPath)

        var device = Device(displayName: "Thor Sim", hostname: "thor.local")
        try db.writer.write { dbConn in
            try device.insert(dbConn)
        }
        let deviceID = try db.reader.read { dbConn in
            try Device.fetchOne(dbConn)!.id!
        }

        let launchProfile = LaunchProfile(
            name: "Nav Bringup",
            package: "nav2_bringup",
            launchFile: "navigation.launch.py",
            arguments: ["slam:=true"],
            environmentOverrides: ["ROS_DOMAIN_ID": "7"],
            expectedReadinessSignals: ["ros2", "sensors"]
        )
        let recipe = DeployRecipe(
            name: "Registry Pull Preflight",
            summary: "Validate registry access and image pull before deploy.",
            variables: [],
            prerequisites: [],
            steps: [
                DeployRecipeStep(
                    type: .registryPreflight,
                    name: "Registry preflight",
                    command: "registry preflight"
                ),
            ],
            rollbackSteps: [],
            readinessAssertions: []
        )
        let manifest = DiagnosticBundleManifest(
            collectedAt: Date(timeIntervalSince1970: 1_775_310_400),
            deviceID: deviceID,
            deviceName: "Thor Sim",
            hostname: "thor.local",
            appVersion: "0.2.0",
            cliVersion: "0.2.0",
            isSimulator: true,
            sections: ["capabilities", "ros2", "streams"]
        )

        let encoder = JSONEncoder()
        var launchRecord = LaunchProfileRecord(
            deviceID: deviceID,
            name: launchProfile.name,
            configJSON: String(decoding: try encoder.encode(launchProfile), as: UTF8.self)
        )
        var recipeRecord = DeployRecipeRecord(
            name: recipe.name,
            recipeJSON: String(decoding: try encoder.encode(recipe), as: UTF8.self)
        )
        var runRecord = RecipeRunRecord(deviceID: deviceID, status: .success, logJSON: "[]", finishedAt: Date())
        var diagnosticRecord = DiagnosticRunRecord(
            deviceID: deviceID,
            archivePath: "/tmp/thor-diagnostics.zip",
            manifestJSON: String(decoding: try encoder.encode(manifest), as: UTF8.self)
        )
        var flowRecord = GuidedFlowProgressRecord(flowID: "first-simulator-session", status: .completed, progress: 1.0)

        try db.writer.write { dbConn in
            try launchRecord.insert(dbConn)
            try recipeRecord.insert(dbConn)
            runRecord.recipeID = recipeRecord.id
            try runRecord.insert(dbConn)
            try diagnosticRecord.insert(dbConn)
            try flowRecord.insert(dbConn)
        }

        let counts = try db.reader.read { dbConn in
            (
                try LaunchProfileRecord.fetchCount(dbConn),
                try DeployRecipeRecord.fetchCount(dbConn),
                try RecipeRunRecord.fetchCount(dbConn),
                try DiagnosticRunRecord.fetchCount(dbConn),
                try GuidedFlowProgressRecord.fetchCount(dbConn)
            )
        }

        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
        #expect(counts.2 == 1)
        #expect(counts.3 == 1)
        #expect(counts.4 == 1)

        let storedLaunch = try db.reader.read { dbConn in
            try LaunchProfileRecord.fetchOne(dbConn)
        }
        let storedRecipe = try db.reader.read { dbConn in
            try DeployRecipeRecord.fetchOne(dbConn)
        }
        let storedDiagnostic = try db.reader.read { dbConn in
            try DiagnosticRunRecord.fetchOne(dbConn)
        }

        #expect(storedLaunch?.deviceID == deviceID)
        #expect(storedRecipe?.name == "Registry Pull Preflight")
        #expect(storedDiagnostic?.archivePath == "/tmp/thor-diagnostics.zip")
    }
}
