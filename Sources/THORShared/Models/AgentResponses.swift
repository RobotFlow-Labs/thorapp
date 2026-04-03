import Foundation

/// Agent /v1/health response.
public struct AgentHealthResponse: Codable, Sendable {
    public let status: String
    public let agentVersion: String
    public let timestamp: String
    public let uptimeSeconds: Int

    enum CodingKeys: String, CodingKey {
        case status
        case agentVersion = "agent_version"
        case timestamp
        case uptimeSeconds = "uptime_seconds"
    }

    public var isHealthy: Bool { status == "healthy" }
}

/// Agent /v1/capabilities response.
public struct AgentCapabilitiesResponse: Codable, Sendable {
    public let agentVersion: String
    public let hardware: HardwareInfo
    public let os: OSInfo
    public let jetpackVersion: String?
    public let dockerVersion: String?
    public let ros2Available: Bool
    public let gpu: GPUInfo
    public let disk: DiskInfo

    enum CodingKeys: String, CodingKey {
        case agentVersion = "agent_version"
        case hardware, os
        case jetpackVersion = "jetpack_version"
        case dockerVersion = "docker_version"
        case ros2Available = "ros2_available"
        case gpu, disk
    }
}

public struct HardwareInfo: Codable, Sendable {
    public let model: String
    public let serial: String
    public let architecture: String
    public let cpuCount: Int
    public let memoryTotalMb: Int

    enum CodingKeys: String, CodingKey {
        case model, serial, architecture
        case cpuCount = "cpu_count"
        case memoryTotalMb = "memory_total_mb"
    }
}

public struct OSInfo: Codable, Sendable {
    public let system: String
    public let release: String
    public let version: String
    public let distro: String
}

public struct GPUInfo: Codable, Sendable {
    public let name: String
    public let memoryTotalMb: Int
    public let memoryUsedMb: Int
    public let temperatureC: Double

    enum CodingKeys: String, CodingKey {
        case name
        case memoryTotalMb = "memory_total_mb"
        case memoryUsedMb = "memory_used_mb"
        case temperatureC = "temperature_c"
    }
}

public struct DiskInfo: Codable, Sendable {
    public let totalGb: Double
    public let freeGb: Double?
    public let usedGb: Double?
    public let percent: Double?

    enum CodingKeys: String, CodingKey {
        case totalGb = "total_gb"
        case freeGb = "free_gb"
        case usedGb = "used_gb"
        case percent
    }
}

/// Agent /v1/metrics response.
public struct AgentMetricsResponse: Codable, Sendable {
    public let timestamp: String
    public let cpu: CPUMetrics
    public let memory: MemoryMetrics
    public let disk: DiskMetrics
    public let temperatures: [String: Double]
    public let network: NetworkMetrics
}

public struct CPUMetrics: Codable, Sendable {
    public let percent: Double
    public let perCpu: [Double]
    public let loadAvg: [Double]

    enum CodingKeys: String, CodingKey {
        case percent
        case perCpu = "per_cpu"
        case loadAvg = "load_avg"
    }
}

public struct MemoryMetrics: Codable, Sendable {
    public let totalMb: Int
    public let usedMb: Int
    public let percent: Double

    enum CodingKeys: String, CodingKey {
        case totalMb = "total_mb"
        case usedMb = "used_mb"
        case percent
    }
}

public struct DiskMetrics: Codable, Sendable {
    public let totalGb: Double
    public let usedGb: Double
    public let percent: Double

    enum CodingKeys: String, CodingKey {
        case totalGb = "total_gb"
        case usedGb = "used_gb"
        case percent
    }
}

public struct NetworkMetrics: Codable, Sendable {
    public let bytesSent: Int
    public let bytesRecv: Int

    enum CodingKeys: String, CodingKey {
        case bytesSent = "bytes_sent"
        case bytesRecv = "bytes_recv"
    }
}

/// Agent /v1/exec response.
public struct AgentExecResponse: Codable, Sendable {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String

    enum CodingKeys: String, CodingKey {
        case exitCode = "exit_code"
        case stdout, stderr
    }
}

// MARK: - Docker

/// Agent /v1/docker/containers response.
public struct DockerContainersResponse: Codable, Sendable {
    public let containers: [DockerContainer]
    public let error: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.containers = try container.decodeIfPresent([DockerContainer].self, forKey: .containers) ?? []
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case containers, error
    }
}

public struct DockerContainer: Codable, Sendable, Identifiable {
    public var id: String
    public let name: String
    public let image: String
    public let status: String
    public let state: String
    public let ports: String
}

/// Agent /v1/docker/action response.
public struct DockerActionResponse: Codable, Sendable {
    public let action: String
    public let container: String
    public let exitCode: Int
    public let stdout: String
    public let stderr: String

    enum CodingKeys: String, CodingKey {
        case action, container
        case exitCode = "exit_code"
        case stdout, stderr
    }
}

/// Agent /v1/docker/logs response.
public struct DockerLogsResponse: Codable, Sendable {
    public let container: String
    public let logs: String
    public let stderr: String?
    public let error: String?
}

// MARK: - Registry

public struct DeviceRegistryStateResponse: Codable, Sendable {
    public let registry: String
    public let trusted: Bool
    public let authenticated: Bool
    public let ready: Bool
    public let needsRestart: Bool
    public let certificatePath: String?
    public let dockerConfigPath: String?
    public let message: String

    enum CodingKeys: String, CodingKey {
        case registry, trusted, authenticated, ready, message
        case needsRestart = "needs_restart"
        case certificatePath = "certificate_path"
        case dockerConfigPath = "docker_config_path"
    }
}

public struct DeviceRegistryApplyResponse: Codable, Sendable {
    public let registry: String
    public let trusted: Bool
    public let authenticated: Bool
    public let ready: Bool
    public let needsRestart: Bool
    public let certificatePath: String?
    public let stdout: String
    public let stderr: String
    public let message: String

    enum CodingKeys: String, CodingKey {
        case registry, trusted, authenticated, ready, stdout, stderr, message
        case needsRestart = "needs_restart"
        case certificatePath = "certificate_path"
    }
}

public struct DeviceRegistryValidationStage: Codable, Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let status: RegistryValidationStatus
    public let message: String

    enum CodingKeys: String, CodingKey {
        case name, status, message
    }
}

public struct DeviceRegistryValidationResponse: Codable, Sendable {
    public let registry: String
    public let status: RegistryValidationStatus
    public let trusted: Bool
    public let authenticated: Bool
    public let ready: Bool
    public let stages: [DeviceRegistryValidationStage]
}

// MARK: - Logs

/// Agent /v1/logs/system response.
public struct LogStreamResponse: Codable, Sendable {
    public let source: String
    public let lines: [String]
    public let count: Int
    public let error: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try container.decode(String.self, forKey: .source)
        self.lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case source, lines, count, error
    }
}

// MARK: - Services

/// Agent /v1/services response.
public struct ServicesResponse: Codable, Sendable {
    public let services: [SystemService]
    public let error: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.services = try container.decodeIfPresent([SystemService].self, forKey: .services) ?? []
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case services, error
    }
}

public struct SystemService: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let load: String
    public let active: String
    public let sub: String
}

// MARK: - ANIMA

/// Agent /v1/anima/modules response.
public struct AnimaModulesResponse: Codable, Sendable {
    public let modules: [ANIMAModuleManifest]
    public let count: Int
}

/// Agent /v1/anima/deploy response.
public struct AnimaDeployResponse: Codable, Sendable {
    public let status: String
    public let pipeline: String
    public let exitCode: Int?
    public let stdout: String?
    public let stderr: String?
    public let composePath: String?

    enum CodingKeys: String, CodingKey {
        case status, pipeline
        case exitCode = "exit_code"
        case stdout, stderr
        case composePath = "compose_path"
    }
}

/// Agent /v1/anima/status response.
public struct AnimaStatusResponse: Codable, Sendable {
    public let pipelines: [AnimaPipelineStatus]
}

public struct AnimaPipelineStatus: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let composePath: String?
    public let containers: [AnimaContainerStatus]?
    public let status: String
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case name
        case composePath = "compose_path"
        case containers, status, error
    }
}

public struct AnimaContainerStatus: Codable, Sendable {
    public let Name: String?
    public let Service: String?
    public let State: String?
    public let Status: String?
}

/// Agent /v1/anima/stop response.
public struct AnimaStopResponse: Codable, Sendable {
    public let status: String
    public let pipeline: String
    public let exitCode: Int?
    public let stdout: String?
    public let stderr: String?

    enum CodingKeys: String, CodingKey {
        case status, pipeline
        case exitCode = "exit_code"
        case stdout, stderr
    }
}

// MARK: - ROS2

/// Agent /v1/ros2/nodes response.
public struct ROS2NodesResponse: Codable, Sendable {
    public let nodes: [String]
    public let count: Int
    public let error: String?
}

/// Agent /v1/ros2/topics response.
public struct ROS2TopicsResponse: Codable, Sendable {
    public let topics: [ROS2Topic]
    public let count: Int
    public let error: String?
}

public struct ROS2Topic: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
}

/// Agent /v1/ros2/services response.
public struct ROS2ServicesResponse: Codable, Sendable {
    public let services: [ROS2Service]
    public let count: Int
    public let error: String?
}

public struct ROS2Service: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
}

/// Agent /v1/system/reboot response.
public struct RebootResponse: Codable, Sendable {
    public let status: String
    public let message: String?
    public let error: String?
}
