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
