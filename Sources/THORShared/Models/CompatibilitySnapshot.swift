import Foundation
import GRDB

/// Point-in-time capability snapshot from a Jetson device.
public struct CompatibilitySnapshot: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64
    public var jetsonModel: String
    public var osRelease: String
    public var jetpackVersion: String?
    public var agentVersion: String
    public var dockerVersion: String?
    public var ros2Presence: Bool
    public var capabilitiesJSON: String?
    public var supportStatus: SupportStatus
    public var capturedAt: Date

    public init(
        id: Int64? = nil,
        deviceID: Int64,
        jetsonModel: String,
        osRelease: String,
        jetpackVersion: String? = nil,
        agentVersion: String,
        dockerVersion: String? = nil,
        ros2Presence: Bool = false,
        capabilitiesJSON: String? = nil,
        supportStatus: SupportStatus = .unknown,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.deviceID = deviceID
        self.jetsonModel = jetsonModel
        self.osRelease = osRelease
        self.jetpackVersion = jetpackVersion
        self.agentVersion = agentVersion
        self.dockerVersion = dockerVersion
        self.ros2Presence = ros2Presence
        self.capabilitiesJSON = capabilitiesJSON
        self.supportStatus = supportStatus
        self.capturedAt = capturedAt
    }
}

public enum SupportStatus: String, Codable, CaseIterable, Sendable {
    case supported
    case supportedWithLimits = "supported_with_limits"
    case unsupported
    case unknown
}

extension CompatibilitySnapshot: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "device_compatibility_snapshots"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns {
        public static let deviceID = Column(CodingKeys.deviceID)
        public static let capturedAt = Column(CodingKeys.capturedAt)
    }
}
