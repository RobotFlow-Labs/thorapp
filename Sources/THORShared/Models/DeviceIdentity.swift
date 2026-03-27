import Foundation
import GRDB

/// Cryptographic and hardware identity for a managed device.
public struct DeviceIdentity: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64
    public var hostKeyFingerprint: String
    public var serialOrMachineID: String?
    public var agentInstanceID: String?

    public init(
        id: Int64? = nil,
        deviceID: Int64,
        hostKeyFingerprint: String,
        serialOrMachineID: String? = nil,
        agentInstanceID: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.hostKeyFingerprint = hostKeyFingerprint
        self.serialOrMachineID = serialOrMachineID
        self.agentInstanceID = agentInstanceID
    }
}

extension DeviceIdentity: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "device_identities"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
