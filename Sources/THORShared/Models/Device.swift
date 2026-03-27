import Foundation
import GRDB

/// A managed Jetson device.
public struct Device: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var displayName: String
    public var hostname: String
    public var lastKnownIP: String?
    public var environment: DeviceEnvironment
    public var tags: String  // comma-separated for MVP
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        displayName: String,
        hostname: String,
        lastKnownIP: String? = nil,
        environment: DeviceEnvironment = .lab,
        tags: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.hostname = hostname
        self.lastKnownIP = lastKnownIP
        self.environment = environment
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum DeviceEnvironment: String, Codable, CaseIterable, Sendable {
    case lab
    case field
    case staging
    case demo
}

// MARK: - GRDB

extension Device: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "devices"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let displayName = Column(CodingKeys.displayName)
        static let hostname = Column(CodingKeys.hostname)
        static let lastKnownIP = Column(CodingKeys.lastKnownIP)
        static let environment = Column(CodingKeys.environment)
        static let tags = Column(CodingKeys.tags)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
