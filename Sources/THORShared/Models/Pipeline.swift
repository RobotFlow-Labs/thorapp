import Foundation
import GRDB

// MARK: - Pipeline Status

public enum PipelineStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case deploying
    case running
    case stopped
    case failed
    case degraded
}

// MARK: - Pipeline

public struct Pipeline: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var name: String
    public var description: String?
    public var modulesJSON: String
    public var deviceID: Int64?
    public var status: PipelineStatus
    public var composeYAML: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        name: String,
        description: String? = nil,
        modules: [ANIMAModuleManifest],
        deviceID: Int64? = nil,
        status: PipelineStatus = .draft,
        composeYAML: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.modulesJSON = (try? String(data: JSONEncoder().encode(modules.map(\.name)), encoding: .utf8)) ?? "[]"
        self.deviceID = deviceID
        self.status = status
        self.composeYAML = composeYAML
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Decode module names from JSON.
    public var moduleNames: [String] {
        guard let data = modulesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

extension Pipeline: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "pipelines"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Pipeline Run

public struct PipelineRun: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var pipelineID: Int64
    public var deviceID: Int64
    public var status: PipelineStatus
    public var startedAt: Date?
    public var finishedAt: Date?
    public var errorSummary: String?
    public var logSnippet: String?

    public init(
        id: Int64? = nil,
        pipelineID: Int64,
        deviceID: Int64,
        status: PipelineStatus = .deploying,
        startedAt: Date? = Date(),
        finishedAt: Date? = nil,
        errorSummary: String? = nil,
        logSnippet: String? = nil
    ) {
        self.id = id
        self.pipelineID = pipelineID
        self.deviceID = deviceID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorSummary = errorSummary
        self.logSnippet = logSnippet
    }
}

extension PipelineRun: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "pipeline_runs"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
