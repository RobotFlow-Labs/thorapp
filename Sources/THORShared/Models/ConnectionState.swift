import Foundation
import GRDB

/// Tracks current connection state for a device.
public struct ConnectionState: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64
    public var status: ConnectionStatus
    public var lastCheckedAt: Date
    public var lastConnectedAt: Date?
    public var failureReason: String?
    public var failureCode: String?

    public init(
        id: Int64? = nil,
        deviceID: Int64,
        status: ConnectionStatus = .unknown,
        lastCheckedAt: Date = Date(),
        lastConnectedAt: Date? = nil,
        failureReason: String? = nil,
        failureCode: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.status = status
        self.lastCheckedAt = lastCheckedAt
        self.lastConnectedAt = lastConnectedAt
        self.failureReason = failureReason
        self.failureCode = failureCode
    }
}

public enum ConnectionStatus: String, Codable, CaseIterable, Sendable {
    case connected
    case degraded
    case disconnected
    case authFailed = "auth_failed"
    case hostKeyMismatch = "host_key_mismatch"
    case unreachable
    case unknown
}

extension ConnectionState: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "connection_states"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
