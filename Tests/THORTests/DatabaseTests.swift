import Testing
import Foundation
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
}
