import Foundation

/// HTTP client for the THOR Jetson Agent API.
/// Connects to the agent via a localhost port (tunneled over SSH).
public struct AgentClient: Sendable {
    private let baseURL: URL

    public init(port: Int) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    // MARK: - Endpoints

    public func health() async throws -> AgentHealthResponse {
        try await get("/v1/health")
    }

    public func capabilities() async throws -> AgentCapabilitiesResponse {
        try await get("/v1/capabilities")
    }

    public func metrics() async throws -> AgentMetricsResponse {
        try await get("/v1/metrics")
    }

    public func exec(command: String, timeout: Int = 30) async throws -> AgentExecResponse {
        try await post("/v1/exec", body: ["command": command, "timeout": timeout])
    }

    // MARK: - Docker

    public func dockerContainers() async throws -> DockerContainersResponse {
        try await get("/v1/docker/containers")
    }

    public func dockerAction(container: String, action: String) async throws -> DockerActionResponse {
        try await post("/v1/docker/action", body: ["container": container, "action": action])
    }

    public func dockerLogs(container: String, tail: Int = 100) async throws -> DockerLogsResponse {
        try await get("/v1/docker/logs/\(container)?tail=\(tail)")
    }

    // MARK: - Logs

    public func systemLogs(lines: Int = 100, unit: String = "") async throws -> LogStreamResponse {
        var path = "/v1/logs/system?lines=\(lines)"
        if !unit.isEmpty { path += "&unit=\(unit)" }
        return try await get(path)
    }

    public func agentLogs(lines: Int = 50) async throws -> LogStreamResponse {
        try await get("/v1/logs/agent?lines=\(lines)")
    }

    // MARK: - Services

    public func services() async throws -> ServicesResponse {
        try await get("/v1/services")
    }

    // MARK: - ANIMA

    public func animaModules() async throws -> AnimaModulesResponse {
        try await get("/v1/anima/modules")
    }

    public func animaDeploy(composeYAML: String, pipelineName: String = "default") async throws -> AnimaDeployResponse {
        try await post("/v1/anima/deploy", body: [
            "compose_yaml": composeYAML,
            "pipeline_name": pipelineName,
        ])
    }

    public func animaStatus() async throws -> AnimaStatusResponse {
        try await get("/v1/anima/status")
    }

    public func animaStop(pipelineName: String = "default") async throws -> AnimaStopResponse {
        try await post("/v1/anima/stop", body: ["pipeline_name": pipelineName])
    }

    // MARK: - ROS2

    public func ros2Nodes() async throws -> ROS2NodesResponse {
        try await get("/v1/ros2/nodes")
    }

    public func ros2Topics() async throws -> ROS2TopicsResponse {
        try await get("/v1/ros2/topics")
    }

    public func ros2Services() async throws -> ROS2ServicesResponse {
        try await get("/v1/ros2/services")
    }

    // MARK: - System

    public func reboot(confirm: String = "REBOOT_CONFIRMED") async throws -> RebootResponse {
        try await post("/v1/system/reboot", body: ["confirm": confirm])
    }

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        // Use string concatenation to preserve query parameters
        let url = URL(string: baseURL.absoluteString + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AgentClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AgentClientError.httpError(statusCode: http.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = URL(string: baseURL.absoluteString + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AgentClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AgentClientError.httpError(statusCode: http.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

public enum AgentClientError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case agentUnhealthy(status: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from agent"
        case .httpError(let code, let body):
            return "Agent HTTP error \(code): \(body)"
        case .agentUnhealthy(let status):
            return "Agent reports unhealthy status: \(status)"
        }
    }
}
