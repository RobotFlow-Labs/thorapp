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

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
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
        let url = baseURL.appendingPathComponent(path)
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
