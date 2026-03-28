import Foundation
import GRDB

/// Per-device SSH and connection configuration.
public struct DeviceConfig: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64
    public var sshUsername: String
    public var sshPort: Int
    public var agentPort: Int
    public var autoConnect: Bool
    public var autoReconnect: Bool
    public var reconnectMaxRetries: Int
    public var healthCheckIntervalSec: Int

    public init(
        id: Int64? = nil,
        deviceID: Int64,
        sshUsername: String = "jetson",
        sshPort: Int = 22,
        agentPort: Int = 8470,
        autoConnect: Bool = false,
        autoReconnect: Bool = true,
        reconnectMaxRetries: Int = 5,
        healthCheckIntervalSec: Int = 15
    ) {
        self.id = id
        self.deviceID = deviceID
        self.sshUsername = sshUsername
        self.sshPort = sshPort
        self.agentPort = agentPort
        self.autoConnect = autoConnect
        self.autoReconnect = autoReconnect
        self.reconnectMaxRetries = reconnectMaxRetries
        self.healthCheckIntervalSec = healthCheckIntervalSec
    }
}

extension DeviceConfig: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "device_configs"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
