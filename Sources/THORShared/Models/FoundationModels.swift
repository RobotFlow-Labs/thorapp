import Foundation
import GRDB

// MARK: - Capability / Readiness

public enum CapabilityState: String, Codable, CaseIterable, Sendable {
    case supported
    case degraded
    case unsupported
    case needsSetup = "needs_setup"

    public var rank: Int {
        switch self {
        case .supported: 0
        case .degraded: 1
        case .needsSetup: 2
        case .unsupported: 3
        }
    }
}

public struct CapabilityGate: Codable, Sendable {
    public var state: CapabilityState
    public var reason: String
    public var actionLabel: String?

    public init(state: CapabilityState, reason: String, actionLabel: String? = nil) {
        self.state = state
        self.reason = reason
        self.actionLabel = actionLabel
    }
}

public struct CapabilityMatrix: Codable, Sendable {
    public var deviceID: Int64?
    public var connectionMode: String
    public var features: [String: CapabilityGate]
    public var updatedAt: Date

    public init(
        deviceID: Int64? = nil,
        connectionMode: String,
        features: [String: CapabilityGate],
        updatedAt: Date = Date()
    ) {
        self.deviceID = deviceID
        self.connectionMode = connectionMode
        self.features = features
        self.updatedAt = updatedAt
    }

    public func gate(for key: String) -> CapabilityGate {
        features[key] ?? CapabilityGate(state: .needsSetup, reason: "Capability not evaluated yet.", actionLabel: "Run setup")
    }
}

public enum ReadinessStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case warning
    case blocked
    case unknown

    public var rank: Int {
        switch self {
        case .ready: 0
        case .warning: 1
        case .unknown: 2
        case .blocked: 3
        }
    }
}

public enum ReadinessCategory: String, Codable, CaseIterable, Sendable {
    case connection
    case agent
    case ros2
    case sensors
    case docker
    case registry
    case gpu
    case storage
}

public struct ReadinessItem: Codable, Identifiable, Sendable {
    public var id: String { category.rawValue }
    public var category: ReadinessCategory
    public var title: String
    public var status: ReadinessStatus
    public var summary: String
    public var detail: String?

    public init(
        category: ReadinessCategory,
        title: String,
        status: ReadinessStatus,
        summary: String,
        detail: String? = nil
    ) {
        self.category = category
        self.title = title
        self.status = status
        self.summary = summary
        self.detail = detail
    }
}

public struct ReadinessReport: Codable, Sendable {
    public var deviceID: Int64?
    public var overall: ReadinessStatus
    public var items: [ReadinessItem]
    public var updatedAt: Date

    public init(
        deviceID: Int64? = nil,
        overall: ReadinessStatus,
        items: [ReadinessItem],
        updatedAt: Date = Date()
    ) {
        self.deviceID = deviceID
        self.overall = overall
        self.items = items
        self.updatedAt = updatedAt
    }
}

public struct SetupCheckResult: Codable, Identifiable, Sendable {
    public var id: String { stage }
    public var stage: String
    public var status: ReadinessStatus
    public var reason: String
    public var actionLabel: String?
    public var rawDetails: String?

    public init(
        stage: String,
        status: ReadinessStatus,
        reason: String,
        actionLabel: String? = nil,
        rawDetails: String? = nil
    ) {
        self.stage = stage
        self.status = status
        self.reason = reason
        self.actionLabel = actionLabel
        self.rawDetails = rawDetails
    }
}

// MARK: - ROS2

public struct ROSGraphSnapshot: Codable, Sendable {
    public var nodes: [ROSGraphNode]
    public var edges: [ROSGraphEdge]
    public var capturedAt: String

    public init(nodes: [ROSGraphNode], edges: [ROSGraphEdge], capturedAt: String) {
        self.nodes = nodes
        self.edges = edges
        self.capturedAt = capturedAt
    }

    enum CodingKeys: String, CodingKey {
        case nodes, edges
        case capturedAt = "captured_at"
    }
}

public struct ROSGraphNode: Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var kind: String
    public var namespace: String?

    public init(name: String, kind: String, namespace: String? = nil) {
        self.name = name
        self.kind = kind
        self.namespace = namespace
    }
}

public struct ROSGraphEdge: Codable, Sendable, Identifiable {
    public var id: String { "\(from)->\(to)" }
    public var from: String
    public var to: String
    public var topic: String
    public var messageType: String

    public init(from: String, to: String, topic: String, messageType: String) {
        self.from = from
        self.to = to
        self.topic = topic
        self.messageType = messageType
    }

    enum CodingKeys: String, CodingKey {
        case from, to, topic
        case messageType = "message_type"
    }
}

public struct ROSParameter: Codable, Sendable, Identifiable {
    public var id: String { "\(node):\(name)" }
    public var node: String
    public var name: String
    public var type: String
    public var value: String
    public var readOnly: Bool

    public init(node: String, name: String, type: String, value: String, readOnly: Bool = false) {
        self.node = node
        self.name = name
        self.type = type
        self.value = value
        self.readOnly = readOnly
    }

    enum CodingKeys: String, CodingKey {
        case node, name, type, value
        case readOnly = "read_only"
    }
}

public struct ROSActionDefinition: Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var type: String
    public var goalSchema: String?
    public var feedbackSchema: String?
    public var resultSchema: String?

    public init(
        name: String,
        type: String,
        goalSchema: String? = nil,
        feedbackSchema: String? = nil,
        resultSchema: String? = nil
    ) {
        self.name = name
        self.type = type
        self.goalSchema = goalSchema
        self.feedbackSchema = feedbackSchema
        self.resultSchema = resultSchema
    }

    enum CodingKeys: String, CodingKey {
        case name, type
        case goalSchema = "goal_schema"
        case feedbackSchema = "feedback_schema"
        case resultSchema = "result_schema"
    }
}

public struct ROSTopicStats: Codable, Sendable, Identifiable {
    public var id: String { topic }
    public var topic: String
    public var messageType: String
    public var publishers: Int
    public var subscribers: Int
    public var hz: Double?
    public var bandwidthBps: Double?
    public var lastMessageAt: String?

    public init(
        topic: String,
        messageType: String,
        publishers: Int,
        subscribers: Int,
        hz: Double? = nil,
        bandwidthBps: Double? = nil,
        lastMessageAt: String? = nil
    ) {
        self.topic = topic
        self.messageType = messageType
        self.publishers = publishers
        self.subscribers = subscribers
        self.hz = hz
        self.bandwidthBps = bandwidthBps
        self.lastMessageAt = lastMessageAt
    }

    enum CodingKeys: String, CodingKey {
        case topic, publishers, subscribers, hz
        case messageType = "message_type"
        case bandwidthBps = "bandwidth_bps"
        case lastMessageAt = "last_message_at"
    }
}

public struct LaunchProfile: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var name: String
    public var package: String
    public var launchFile: String
    public var arguments: [String]
    public var environmentOverrides: [String: String]
    public var expectedReadinessSignals: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        name: String,
        package: String,
        launchFile: String,
        arguments: [String] = [],
        environmentOverrides: [String: String] = [:],
        expectedReadinessSignals: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.package = package
        self.launchFile = launchFile
        self.arguments = arguments
        self.environmentOverrides = environmentOverrides
        self.expectedReadinessSignals = expectedReadinessSignals
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Streams

public enum StreamKind: String, Codable, CaseIterable, Sendable {
    case image
    case scan
}

public enum StreamOrigin: String, Codable, CaseIterable, Sendable {
    case deviceCamera = "device_camera"
    case bridgedCamera = "bridged_camera"
    case rosImageTopic = "ros_image_topic"
    case rosLaserScanTopic = "ros_laserscan_topic"
}

public struct StreamSource: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: StreamKind
    public var origin: StreamOrigin
    public var topic: String?
    public var devicePath: String?
    public var messageType: String?
    public var width: Int?
    public var height: Int?
    public var nominalFPS: Double?

    public init(
        id: String,
        name: String,
        kind: StreamKind,
        origin: StreamOrigin,
        topic: String? = nil,
        devicePath: String? = nil,
        messageType: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        nominalFPS: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.origin = origin
        self.topic = topic
        self.devicePath = devicePath
        self.messageType = messageType
        self.width = width
        self.height = height
        self.nominalFPS = nominalFPS
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, origin, topic, width, height
        case devicePath = "device_path"
        case messageType = "message_type"
        case nominalFPS = "nominal_fps"
    }
}

public struct StreamHealth: Codable, Sendable {
    public var sourceID: String
    public var status: ReadinessStatus
    public var fps: Double?
    public var width: Int?
    public var height: Int?
    public var lastFrameAt: String?
    public var droppedFrames: Int
    public var stale: Bool
    public var transportHealthy: Bool
    public var timestampsSane: Bool
    public var expectedRate: Bool

    public init(
        sourceID: String,
        status: ReadinessStatus,
        fps: Double? = nil,
        width: Int? = nil,
        height: Int? = nil,
        lastFrameAt: String? = nil,
        droppedFrames: Int = 0,
        stale: Bool = false,
        transportHealthy: Bool = true,
        timestampsSane: Bool = true,
        expectedRate: Bool = true
    ) {
        self.sourceID = sourceID
        self.status = status
        self.fps = fps
        self.width = width
        self.height = height
        self.lastFrameAt = lastFrameAt
        self.droppedFrames = droppedFrames
        self.stale = stale
        self.transportHealthy = transportHealthy
        self.timestampsSane = timestampsSane
        self.expectedRate = expectedRate
    }

    enum CodingKeys: String, CodingKey {
        case status, fps, width, height, stale
        case sourceID = "source_id"
        case lastFrameAt = "last_frame_at"
        case droppedFrames = "dropped_frames"
        case transportHealthy = "transport_healthy"
        case timestampsSane = "timestamps_sane"
        case expectedRate = "expected_rate"
    }
}

public struct ImageFrameMetadata: Codable, Sendable {
    public var sourceID: String
    public var width: Int
    public var height: Int
    public var format: String
    public var fps: Double?
    public var capturedAt: String
    public var byteCount: Int
    public var previewPath: String?

    public init(
        sourceID: String,
        width: Int,
        height: Int,
        format: String,
        fps: Double? = nil,
        capturedAt: String,
        byteCount: Int,
        previewPath: String? = nil
    ) {
        self.sourceID = sourceID
        self.width = width
        self.height = height
        self.format = format
        self.fps = fps
        self.capturedAt = capturedAt
        self.byteCount = byteCount
        self.previewPath = previewPath
    }

    enum CodingKeys: String, CodingKey {
        case width, height, format, fps
        case sourceID = "source_id"
        case capturedAt = "captured_at"
        case byteCount = "byte_count"
        case previewPath = "preview_path"
    }
}

public struct LaserScanFrame: Codable, Sendable {
    public var sourceID: String
    public var angleMin: Double
    public var angleMax: Double
    public var angleIncrement: Double
    public var rangeMin: Double
    public var rangeMax: Double
    public var ranges: [Double]
    public var intensities: [Double]
    public var capturedAt: String

    public init(
        sourceID: String,
        angleMin: Double,
        angleMax: Double,
        angleIncrement: Double,
        rangeMin: Double,
        rangeMax: Double,
        ranges: [Double],
        intensities: [Double] = [],
        capturedAt: String
    ) {
        self.sourceID = sourceID
        self.angleMin = angleMin
        self.angleMax = angleMax
        self.angleIncrement = angleIncrement
        self.rangeMin = rangeMin
        self.rangeMax = rangeMax
        self.ranges = ranges
        self.intensities = intensities
        self.capturedAt = capturedAt
    }

    enum CodingKeys: String, CodingKey {
        case ranges, intensities
        case sourceID = "source_id"
        case angleMin = "angle_min"
        case angleMax = "angle_max"
        case angleIncrement = "angle_increment"
        case rangeMin = "range_min"
        case rangeMax = "range_max"
        case capturedAt = "captured_at"
    }
}

// MARK: - Deploy

public enum DeployRecipeStepType: String, Codable, CaseIterable, Sendable {
    case registryPreflight = "registryPreflight"
    case dockerPull = "dockerPull"
    case dockerComposeUp = "dockerComposeUp"
    case dockerComposeDown = "dockerComposeDown"
    case ros2LaunchStart = "ros2LaunchStart"
    case ros2LaunchStop = "ros2LaunchStop"
    case ros2BagRecord = "ros2BagRecord"
    case copyFiles = "copyFiles"
    case modelWarmup = "modelWarmup"
    case healthCheck = "healthCheck"
    case readOnlyShell = "readOnlyShell"
}

public struct DeployRecipeVariable: Codable, Sendable, Identifiable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var defaultValue: String?
    public var required: Bool

    public init(key: String, label: String, defaultValue: String? = nil, required: Bool = false) {
        self.key = key
        self.label = label
        self.defaultValue = defaultValue
        self.required = required
    }
}

public struct DeployRecipePrerequisite: Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var command: String
    public var expectedSubstring: String?

    public init(name: String, command: String, expectedSubstring: String? = nil) {
        self.name = name
        self.command = command
        self.expectedSubstring = expectedSubstring
    }
}

public struct DeployRecipeAssertion: Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var command: String
    public var expectedSubstring: String?

    public init(name: String, command: String, expectedSubstring: String? = nil) {
        self.name = name
        self.command = command
        self.expectedSubstring = expectedSubstring
    }
}

public struct DeployRecipeStep: Codable, Sendable, Identifiable {
    public var id: UUID
    public var type: DeployRecipeStepType
    public var name: String
    public var command: String
    public var timeout: Int
    public var stopOnFailure: Bool

    public init(
        id: UUID = UUID(),
        type: DeployRecipeStepType,
        name: String,
        command: String,
        timeout: Int = 30,
        stopOnFailure: Bool = true
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.command = command
        self.timeout = timeout
        self.stopOnFailure = stopOnFailure
    }
}

public struct DeployRecipe: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var name: String
    public var summary: String
    public var icon: String
    public var variables: [DeployRecipeVariable]
    public var prerequisites: [DeployRecipePrerequisite]
    public var steps: [DeployRecipeStep]
    public var rollbackSteps: [DeployRecipeStep]
    public var readinessAssertions: [DeployRecipeAssertion]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        name: String,
        summary: String,
        icon: String = "play.rectangle",
        variables: [DeployRecipeVariable] = [],
        prerequisites: [DeployRecipePrerequisite] = [],
        steps: [DeployRecipeStep] = [],
        rollbackSteps: [DeployRecipeStep] = [],
        readinessAssertions: [DeployRecipeAssertion] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.icon = icon
        self.variables = variables
        self.prerequisites = prerequisites
        self.steps = steps
        self.rollbackSteps = rollbackSteps
        self.readinessAssertions = readinessAssertions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum RecipeRunStatus: String, Codable, CaseIterable, Sendable {
    case created
    case running
    case success
    case failed
    case rolledBack = "rolled_back"
}

public struct RecipeRunLogLine: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var timestamp: String
    public var level: String
    public var message: String

    public init(timestamp: String, level: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

public struct RecipeRun: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64
    public var recipeID: Int64?
    public var recipeName: String
    public var status: RecipeRunStatus
    public var logs: [RecipeRunLogLine]
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: Int64? = nil,
        deviceID: Int64,
        recipeID: Int64? = nil,
        recipeName: String,
        status: RecipeRunStatus = .created,
        logs: [RecipeRunLogLine] = [],
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.recipeID = recipeID
        self.recipeName = recipeName
        self.status = status
        self.logs = logs
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

// MARK: - Diagnostics / Guided Flows

public struct DiagnosticBundleManifest: Codable, Sendable {
    public var collectedAt: Date
    public var deviceID: Int64?
    public var deviceName: String
    public var hostname: String
    public var appVersion: String
    public var cliVersion: String
    public var isSimulator: Bool
    public var sections: [String]

    public init(
        collectedAt: Date = Date(),
        deviceID: Int64? = nil,
        deviceName: String,
        hostname: String,
        appVersion: String,
        cliVersion: String,
        isSimulator: Bool,
        sections: [String]
    ) {
        self.collectedAt = collectedAt
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.hostname = hostname
        self.appVersion = appVersion
        self.cliVersion = cliVersion
        self.isSimulator = isSimulator
        self.sections = sections
    }
}

public enum GuidedFlowStatus: String, Codable, CaseIterable, Sendable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed
}

public struct GuidedFlowStep: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var title: String
    public var detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public struct GuidedFlow: Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var steps: [GuidedFlowStep]

    public init(id: String, title: String, summary: String, steps: [GuidedFlowStep]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.steps = steps
    }
}

// MARK: - Database Records

public struct LaunchProfileRecord: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64?
    public var name: String
    public var configJSON: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        deviceID: Int64? = nil,
        name: String,
        configJSON: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.deviceID = deviceID
        self.name = name
        self.configJSON = configJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension LaunchProfileRecord: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "launch_profiles"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct DeployRecipeRecord: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var name: String
    public var recipeJSON: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        name: String,
        recipeJSON: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.recipeJSON = recipeJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension DeployRecipeRecord: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "deploy_recipes"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct RecipeRunRecord: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64?
    public var recipeID: Int64?
    public var status: RecipeRunStatus
    public var logJSON: String
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: Int64? = nil,
        deviceID: Int64? = nil,
        recipeID: Int64? = nil,
        status: RecipeRunStatus,
        logJSON: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.recipeID = recipeID
        self.status = status
        self.logJSON = logJSON
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

extension RecipeRunRecord: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "recipe_runs"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct DiagnosticRunRecord: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var deviceID: Int64?
    public var archivePath: String
    public var manifestJSON: String
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        deviceID: Int64? = nil,
        archivePath: String,
        manifestJSON: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.deviceID = deviceID
        self.archivePath = archivePath
        self.manifestJSON = manifestJSON
        self.createdAt = createdAt
    }
}

extension DiagnosticRunRecord: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "diagnostic_runs"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct GuidedFlowProgressRecord: Codable, Identifiable, Sendable {
    public var id: Int64?
    public var flowID: String
    public var status: GuidedFlowStatus
    public var progress: Double
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        flowID: String,
        status: GuidedFlowStatus,
        progress: Double,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.flowID = flowID
        self.status = status
        self.progress = progress
        self.updatedAt = updatedAt
    }
}

extension GuidedFlowProgressRecord: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "guided_flow_progress"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
