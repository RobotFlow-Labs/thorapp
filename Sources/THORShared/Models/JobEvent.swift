import Foundation
import GRDB

/// An event within a job's lifecycle for auditability.
public struct JobEvent: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var jobID: Int64
    public var eventType: String
    public var message: String
    public var timestamp: Date

    public init(
        id: Int64? = nil,
        jobID: Int64,
        eventType: String,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.jobID = jobID
        self.eventType = eventType
        self.message = message
        self.timestamp = timestamp
    }
}

extension JobEvent: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "job_events"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
