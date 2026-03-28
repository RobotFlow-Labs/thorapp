import Foundation
import GRDB

// MARK: - Jetson Platform

public enum JetsonPlatform: String, Codable, CaseIterable, Sendable {
    case thor = "jetson_thor"
    case orinNX = "jetson_orin_nx"
    case orinNano = "jetson_orin_nano"
    case agxOrin = "jetson_agx_orin"
    case generic = "jetson"

    public var displayName: String {
        switch self {
        case .thor: "Jetson Thor"
        case .orinNX: "Jetson Orin NX"
        case .orinNano: "Jetson Orin Nano"
        case .agxOrin: "Jetson AGX Orin"
        case .generic: "Jetson (Generic)"
        }
    }

    /// Match a model string from capabilities to a platform.
    public static func from(model: String) -> JetsonPlatform {
        let lower = model.lowercased()
        if lower.contains("thor") { return .thor }
        if lower.contains("orin nx") { return .orinNX }
        if lower.contains("orin nano") { return .orinNano }
        if lower.contains("agx orin") { return .agxOrin }
        if lower.contains("jetson") { return .generic }
        return .generic
    }
}

// MARK: - ANIMA Module Manifest (parsed from agent JSON)

public struct ANIMAModuleManifest: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let schemaVersion: String
    public let name: String
    public let version: String
    public let displayName: String
    public let description: String
    public let category: String
    public let containerImage: String

    public let capabilities: [ModuleCapability]
    public let inputs: [ModuleIO]
    public let outputs: [ModuleIO]
    public let hardwarePlatforms: [PlatformSupport]
    public let performanceProfiles: [PerformanceProfile]

    public let failureMode: String?
    public let timeoutMs: Int?
    public let healthTopic: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case name, version
        case displayName = "display_name"
        case description, category
        case containerImage = "container_image"
        case capabilities, inputs, outputs
        case hardwarePlatforms = "hardware_platforms"
        case performanceProfiles = "performance_profiles"
        case failureMode = "failure_mode"
        case timeoutMs = "timeout_ms"
        case healthTopic = "health_topic"
    }

    /// Check if this module supports the given Jetson platform.
    public func supportsJetson(_ platform: JetsonPlatform) -> Bool {
        hardwarePlatforms.contains { p in
            p.name == platform.rawValue ||
            p.name == "jetson" ||
            p.name.lowercased().contains(platform.rawValue.replacingOccurrences(of: "jetson_", with: ""))
        }
    }

    /// Get the preferred backend for a platform.
    public func preferredBackend(for platform: JetsonPlatform) -> String {
        if let match = hardwarePlatforms.first(where: { $0.name == platform.rawValue || $0.name == "jetson" }) {
            // Prefer TensorRT > CUDA > CPU
            if match.backends.contains("tensorrt") { return "tensorrt" }
            if match.backends.contains("cuda") { return "cuda" }
            return match.backends.first ?? "cpu"
        }
        return "cpu"
    }
}

public struct ModuleCapability: Codable, Sendable {
    public let type: String
    public let subtype: String?
}

public struct ModuleIO: Codable, Sendable {
    public let name: String
    public let ros2Type: String
    public let encoding: [String]?
    public let typicalHz: Double?
    public let minHz: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case ros2Type = "ros2_type"
        case encoding
        case typicalHz = "typical_hz"
        case minHz = "min_hz"
    }
}

public struct PlatformSupport: Codable, Sendable {
    public let name: String
    public let backends: [String]
}

public struct PerformanceProfile: Codable, Sendable {
    public let platform: String
    public let model: String?
    public let backend: String
    public let fps: Double?
    public let latencyP50Ms: Double?
    public let memoryMb: Int?

    enum CodingKeys: String, CodingKey {
        case platform, model, backend, fps
        case latencyP50Ms = "latency_p50_ms"
        case memoryMb = "memory_mb"
    }
}

// MARK: - ANIMA Module DB Record

public struct ANIMAModuleRecord: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64
    public var name: String
    public var version: String
    public var displayName: String?
    public var category: String?
    public var containerImage: String
    public var capabilitiesJSON: String?
    public var hardwareSupportJSON: String?
    public var performanceJSON: String?
    public var installedAt: Date

    public init(
        id: Int64? = nil,
        deviceID: Int64,
        manifest: ANIMAModuleManifest,
        installedAt: Date = Date()
    ) {
        self.id = id
        self.deviceID = deviceID
        self.name = manifest.name
        self.version = manifest.version
        self.displayName = manifest.displayName
        self.category = manifest.category
        self.containerImage = manifest.containerImage
        self.capabilitiesJSON = try? String(data: JSONEncoder().encode(manifest.capabilities), encoding: .utf8)
        self.hardwareSupportJSON = try? String(data: JSONEncoder().encode(manifest.hardwarePlatforms), encoding: .utf8)
        self.performanceJSON = try? String(data: JSONEncoder().encode(manifest.performanceProfiles), encoding: .utf8)
        self.installedAt = installedAt
    }
}

extension ANIMAModuleRecord: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "anima_modules"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
