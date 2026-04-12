import Foundation
import GRDB

#if canImport(CSQLite)
import CSQLite
#elseif canImport(SQLite3)
import SQLite3
#endif

/// Manages the shared SQLite database for THOR.
/// Used by both THORApp and THORCore via the app group container.
public final class DatabaseManager: Sendable {
    private let dbPool: DatabasePool
    public static let supportDirectoryEnvironmentKey = "THOR_APP_SUPPORT_DIR"

    public var reader: DatabaseReader { dbPool }
    public var writer: DatabaseWriter { dbPool }

    /// Open or create the database at the given path.
    public init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable persistent WAL for cross-process reads
            var flag: CInt = 1
            _ = withUnsafeMutablePointer(to: &flag) { flagP in
                sqlite3_file_control(db.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, flagP)
            }
        }

        dbPool = try DatabasePool(path: path, configuration: config)
        try Self.migrator.migrate(dbPool)
    }

    /// In-memory database for testing.
    public static func inMemory() throws -> DatabaseManager {
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        try migrator.migrate(dbQueue)
        // Wrap in a way tests can use — for production we use DatabasePool
        return try DatabaseManager(path: ":memory:")
    }

    // MARK: - Migrations

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial") { db in
            // devices
            try db.create(table: "devices") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("displayName", .text).notNull()
                t.column("hostname", .text).notNull()
                t.column("lastKnownIP", .text)
                t.column("environment", .text).notNull().defaults(to: "lab")
                t.column("tags", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // device_identities
            try db.create(table: "device_identities") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer).notNull()
                    .references("devices", onDelete: .cascade)
                t.column("hostKeyFingerprint", .text).notNull()
                t.column("serialOrMachineID", .text)
                t.column("agentInstanceID", .text)
            }

            // device_compatibility_snapshots
            try db.create(table: "device_compatibility_snapshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer).notNull()
                    .references("devices", onDelete: .cascade)
                t.column("jetsonModel", .text).notNull()
                t.column("osRelease", .text).notNull()
                t.column("jetpackVersion", .text)
                t.column("agentVersion", .text).notNull()
                t.column("dockerVersion", .text)
                t.column("ros2Presence", .boolean).notNull().defaults(to: false)
                t.column("capabilitiesJSON", .text)
                t.column("supportStatus", .text).notNull().defaults(to: "unknown")
                t.column("capturedAt", .datetime).notNull()
            }

            // connection_states
            try db.create(table: "connection_states") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer).notNull().unique()
                    .references("devices", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "unknown")
                t.column("lastCheckedAt", .datetime).notNull()
                t.column("lastConnectedAt", .datetime)
                t.column("failureReason", .text)
                t.column("failureCode", .text)
            }

            // jobs
            try db.create(table: "jobs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer).notNull()
                    .references("devices", onDelete: .cascade)
                t.column("jobType", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "created")
                t.column("payloadJSON", .text)
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
                t.column("errorCode", .text)
                t.column("errorSummary", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // job_events
            try db.create(table: "job_events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("jobID", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("eventType", .text).notNull()
                t.column("message", .text).notNull()
                t.column("timestamp", .datetime).notNull()
            }

            // transfer_records
            try db.create(table: "transfer_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("jobID", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("deviceID", .integer).notNull()
                    .references("devices", onDelete: .cascade)
                t.column("sourcePath", .text).notNull()
                t.column("targetPath", .text).notNull()
                t.column("bytesTotal", .integer)
                t.column("bytesTransferred", .integer)
                t.column("verified", .boolean).notNull().defaults(to: false)
                t.column("checksum", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // runtime_profiles
            try db.create(table: "runtime_profiles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer)
                    .references("devices", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("profileType", .text).notNull()
                t.column("configJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // operator_preferences
            try db.create(table: "operator_preferences") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("key", .text).notNull().unique()
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2_anima") { db in
            // anima_modules
            try db.create(table: "anima_modules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer)
                    .references("devices", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("version", .text).notNull()
                t.column("displayName", .text)
                t.column("category", .text)
                t.column("containerImage", .text).notNull()
                t.column("capabilitiesJSON", .text)
                t.column("hardwareSupportJSON", .text)
                t.column("performanceJSON", .text)
                t.column("installedAt", .datetime).notNull()
            }

            // pipelines
            try db.create(table: "pipelines") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("modulesJSON", .text).notNull()
                t.column("deviceID", .integer)
                    .references("devices", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "draft")
                t.column("composeYAML", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // pipeline_runs
            try db.create(table: "pipeline_runs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pipelineID", .integer)
                    .references("pipelines", onDelete: .cascade)
                t.column("deviceID", .integer)
                    .references("devices", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "deploying")
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
                t.column("errorSummary", .text)
                t.column("logSnippet", .text)
            }
        }

        migrator.registerMigration("v3_device_config") { db in
            try db.create(table: "device_configs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer).notNull().unique()
                    .references("devices", onDelete: .cascade)
                t.column("sshUsername", .text).notNull().defaults(to: "jetson")
                t.column("sshPort", .integer).notNull().defaults(to: 22)
                t.column("agentPort", .integer).notNull().defaults(to: 8470)
                t.column("autoConnect", .boolean).notNull().defaults(to: false)
                t.column("autoReconnect", .boolean).notNull().defaults(to: true)
                t.column("reconnectMaxRetries", .integer).notNull().defaults(to: 5)
                t.column("healthCheckIntervalSec", .integer).notNull().defaults(to: 15)
            }
        }

        migrator.registerMigration("v4_registry_profiles") { db in
            try db.create(table: "registry_profiles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("displayName", .text).notNull()
                t.column("host", .text).notNull()
                t.column("port", .integer).notNull().defaults(to: 443)
                t.column("scheme", .text).notNull().defaults(to: "https")
                t.column("username", .text)
                t.column("repositoryNamespace", .text).notNull().defaults(to: "")
                t.column("caCertificatePath", .text)
                t.column("caCertificateFingerprintSHA256", .text)
                t.column("caCertificateFingerprintSHA1", .text)
                t.column("caCertificateCommonName", .text)
                t.column("caCertificateIssuer", .text)
                t.column("caCertificateExpiresAt", .datetime)
                t.column("lastValidatedAt", .datetime)
                t.column("lastValidationStatus", .text).notNull().defaults(to: "unknown")
                t.column("lastValidationMessage", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v5_v0_2_foundation") { db in
            try db.create(table: "launch_profiles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer)
                    .references("devices", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("configJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "deploy_recipes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("recipeJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "recipe_runs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer)
                    .references("devices", onDelete: .cascade)
                t.column("recipeID", .integer)
                    .references("deploy_recipes", onDelete: .setNull)
                t.column("status", .text).notNull()
                t.column("logJSON", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("finishedAt", .datetime)
            }

            try db.create(table: "diagnostic_runs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceID", .integer)
                    .references("devices", onDelete: .cascade)
                t.column("archivePath", .text).notNull()
                t.column("manifestJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "guided_flow_progress") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("flowID", .text).notNull().unique()
                t.column("status", .text).notNull()
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("updatedAt", .datetime).notNull()
            }
        }

        return migrator
    }

    // MARK: - Convenience

    /// Default THOR app support directory, with an explicit override for tests
    /// and a temporary fallback when Application Support is unavailable.
    public static var supportDirectoryURL: URL {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment[supportDirectoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let thorDirectory = appSupport.appendingPathComponent("THOR", isDirectory: true)
            do {
                try fileManager.createDirectory(at: thorDirectory, withIntermediateDirectories: true)
                return thorDirectory
            } catch {
                // Fall through to a writable emergency location below.
            }
        }

        let fallback = fileManager.temporaryDirectory.appendingPathComponent("THOR", isDirectory: true)
        try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Default database path inside the THOR support directory.
    public static var defaultPath: String {
        supportDirectoryURL.appendingPathComponent("thor.sqlite").path
    }
}
