import Foundation
import GRDB

/// A typed remote operation with structured lifecycle.
public struct Job: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64
    public var jobType: JobType
    public var status: JobStatus
    public var payloadJSON: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var errorCode: String?
    public var errorSummary: String?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        deviceID: Int64,
        jobType: JobType,
        status: JobStatus = .created,
        payloadJSON: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorCode: String? = nil,
        errorSummary: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.deviceID = deviceID
        self.jobType = jobType
        self.status = status
        self.payloadJSON = payloadJSON
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorCode = errorCode
        self.errorSummary = errorSummary
        self.createdAt = createdAt
    }
}

public enum JobType: String, Codable, CaseIterable, Sendable {
    case enroll
    case agentInstall = "agent_install"
    case agentUpgrade = "agent_upgrade"
    case healthCheck = "health_check"
    case fileSync = "file_sync"
    case fileUpload = "file_upload"
    case commandExec = "command_exec"
    case deploy
    case reboot
    case compatibilityFetch = "compatibility_fetch"
}

public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case created
    case queued
    case running
    case success
    case failed
    case cancelled
    case partial
}

extension Job: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "jobs"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
