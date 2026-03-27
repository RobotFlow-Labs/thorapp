import Foundation
import GRDB

/// Record of a file transfer operation.
public struct TransferRecord: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var jobID: Int64
    public var deviceID: Int64
    public var sourcePath: String
    public var targetPath: String
    public var bytesTotal: Int64?
    public var bytesTransferred: Int64?
    public var verified: Bool
    public var checksum: String?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        jobID: Int64,
        deviceID: Int64,
        sourcePath: String,
        targetPath: String,
        bytesTotal: Int64? = nil,
        bytesTransferred: Int64? = nil,
        verified: Bool = false,
        checksum: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.jobID = jobID
        self.deviceID = deviceID
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.bytesTotal = bytesTotal
        self.bytesTransferred = bytesTransferred
        self.verified = verified
        self.checksum = checksum
        self.createdAt = createdAt
    }
}

extension TransferRecord: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "transfer_records"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
