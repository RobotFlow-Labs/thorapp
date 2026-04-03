import Foundation
import GRDB

public enum RegistryScheme: String, Codable, CaseIterable, Sendable {
    case https
    case http
}

public enum RegistryValidationStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case pass
    case warning
    case fail

    public var rank: Int {
        switch self {
        case .unknown: 0
        case .pass: 1
        case .warning: 2
        case .fail: 3
        }
    }
}

public struct RegistryProfile: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var displayName: String
    public var host: String
    public var port: Int
    public var scheme: RegistryScheme
    public var username: String?
    public var repositoryNamespace: String
    public var caCertificatePath: String?
    public var caCertificateFingerprintSHA256: String?
    public var caCertificateFingerprintSHA1: String?
    public var caCertificateCommonName: String?
    public var caCertificateIssuer: String?
    public var caCertificateExpiresAt: Date?
    public var lastValidatedAt: Date?
    public var lastValidationStatus: RegistryValidationStatus
    public var lastValidationMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        displayName: String,
        host: String,
        port: Int = 443,
        scheme: RegistryScheme = .https,
        username: String? = nil,
        repositoryNamespace: String = "",
        caCertificatePath: String? = nil,
        caCertificateFingerprintSHA256: String? = nil,
        caCertificateFingerprintSHA1: String? = nil,
        caCertificateCommonName: String? = nil,
        caCertificateIssuer: String? = nil,
        caCertificateExpiresAt: Date? = nil,
        lastValidatedAt: Date? = nil,
        lastValidationStatus: RegistryValidationStatus = .unknown,
        lastValidationMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.scheme = scheme
        self.username = username
        self.repositoryNamespace = repositoryNamespace
        self.caCertificatePath = caCertificatePath
        self.caCertificateFingerprintSHA256 = caCertificateFingerprintSHA256
        self.caCertificateFingerprintSHA1 = caCertificateFingerprintSHA1
        self.caCertificateCommonName = caCertificateCommonName
        self.caCertificateIssuer = caCertificateIssuer
        self.caCertificateExpiresAt = caCertificateExpiresAt
        self.lastValidatedAt = lastValidatedAt
        self.lastValidationStatus = lastValidationStatus
        self.lastValidationMessage = lastValidationMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var endpointLabel: String {
        "\(scheme.rawValue)://\(host):\(port)"
    }

    public var registryAddress: String {
        "\(host):\(port)"
    }

    public var v2URL: URL? {
        URL(string: "\(scheme.rawValue)://\(host):\(port)/v2/")
    }
}

extension RegistryProfile: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "registry_profiles"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let displayName = Column(CodingKeys.displayName)
        public static let host = Column(CodingKeys.host)
        public static let port = Column(CodingKeys.port)
        public static let scheme = Column(CodingKeys.scheme)
        public static let username = Column(CodingKeys.username)
        public static let repositoryNamespace = Column(CodingKeys.repositoryNamespace)
        public static let caCertificatePath = Column(CodingKeys.caCertificatePath)
        public static let caCertificateFingerprintSHA256 = Column(CodingKeys.caCertificateFingerprintSHA256)
        public static let caCertificateFingerprintSHA1 = Column(CodingKeys.caCertificateFingerprintSHA1)
        public static let caCertificateCommonName = Column(CodingKeys.caCertificateCommonName)
        public static let caCertificateIssuer = Column(CodingKeys.caCertificateIssuer)
        public static let caCertificateExpiresAt = Column(CodingKeys.caCertificateExpiresAt)
        public static let lastValidatedAt = Column(CodingKeys.lastValidatedAt)
        public static let lastValidationStatus = Column(CodingKeys.lastValidationStatus)
        public static let lastValidationMessage = Column(CodingKeys.lastValidationMessage)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

public struct RegistryValidationStage: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let status: RegistryValidationStatus
    public let message: String

    public init(name: String, status: RegistryValidationStatus, message: String) {
        self.name = name
        self.status = status
        self.message = message
    }
}

public struct RegistryValidationReport: Sendable {
    public let profileID: Int64?
    public let endpoint: String
    public let status: RegistryValidationStatus
    public let stages: [RegistryValidationStage]

    public init(
        profileID: Int64?,
        endpoint: String,
        status: RegistryValidationStatus,
        stages: [RegistryValidationStage]
    ) {
        self.profileID = profileID
        self.endpoint = endpoint
        self.status = status
        self.stages = stages
    }

    public var summary: String {
        stages.last(where: { $0.status == status })?.message ?? "Validation complete"
    }
}
