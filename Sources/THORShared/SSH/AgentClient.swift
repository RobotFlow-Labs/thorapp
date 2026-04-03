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

    // MARK: - Power

    public func powerMode() async throws -> PowerModeResponse {
        try await get("/v1/power/mode")
    }

    public func setPowerMode(_ mode: Int) async throws -> PowerModeResponse {
        try await post("/v1/power/mode", body: ["mode": mode])
    }

    public func powerClocks() async throws -> PowerClocksResponse {
        try await get("/v1/power/clocks")
    }

    public func setPowerClocks(enable: Bool) async throws -> PowerClocksResponse {
        try await post("/v1/power/clocks", body: ["enable": enable])
    }

    public func fanStatus() async throws -> FanStatusResponse {
        try await get("/v1/power/fan")
    }

    public func setFanSpeed(_ pwm: Int) async throws -> FanStatusResponse {
        try await post("/v1/power/fan", body: ["speed": pwm])
    }

    // MARK: - System

    public func systemInfo() async throws -> SystemInfoResponse {
        try await get("/v1/system/info")
    }

    public func packages() async throws -> PackagesResponse {
        try await get("/v1/system/packages")
    }

    public func packageAction(_ action: String) async throws -> PackageActionResponse {
        try await post("/v1/system/packages", body: ["action": action])
    }

    public func users() async throws -> UsersResponse {
        try await get("/v1/system/users")
    }

    public func reboot(confirm: String = "REBOOT_CONFIRMED") async throws -> RebootResponse {
        try await post("/v1/system/reboot", body: ["confirm": confirm])
    }

    // MARK: - Storage

    public func disks() async throws -> DisksResponse {
        try await get("/v1/storage/disks")
    }

    public func swap() async throws -> SwapResponse {
        try await get("/v1/storage/swap")
    }

    public func setSwap(action: String, file: String = "/swapfile") async throws -> SwapResponse {
        try await post("/v1/storage/swap", body: ["action": action, "file": file])
    }

    // MARK: - Network

    public func networkInterfaces() async throws -> NetworkInterfacesResponse {
        try await get("/v1/network/interfaces")
    }

    public func wifiList() async throws -> WifiListResponse {
        try await get("/v1/network/wifi")
    }

    public func wifiConnect(ssid: String, password: String) async throws -> WifiConnectResponse {
        try await post("/v1/network/wifi", body: ["ssid": ssid, "password": password])
    }

    // MARK: - Hardware

    public func cameras() async throws -> CameraListResponse {
        try await get("/v1/hardware/cameras")
    }

    public func gpio() async throws -> GPIOResponse {
        try await get("/v1/hardware/gpio")
    }

    public func i2cScan() async throws -> I2CResponse {
        try await get("/v1/hardware/i2c")
    }

    public func usbDevices() async throws -> USBDevicesResponse {
        try await get("/v1/hardware/usb")
    }

    public func serialPorts() async throws -> SerialPortsResponse {
        try await get("/v1/hardware/serial")
    }

    // MARK: - GPU & Models

    public func gpuDetail() async throws -> GPUDetailResponse {
        try await get("/v1/gpu/info")
    }

    public func tensorrtEngines() async throws -> TensorRTEnginesResponse {
        try await get("/v1/gpu/tensorrt/engines")
    }

    public func modelList() async throws -> ModelListResponse {
        try await get("/v1/models/list")
    }

    // MARK: - Docker Extended

    public func dockerImages() async throws -> DockerImagesResponse {
        try await get("/v1/docker/images")
    }

    public func dockerPull(image: String) async throws -> DockerActionResponse {
        try await post("/v1/docker/pull", body: ["image": image])
    }

    // MARK: - Registry

    public func deviceRegistryStatus(registryAddress: String, scheme: RegistryScheme = .https) async throws -> DeviceRegistryStateResponse {
        let encodedRegistry = registryAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? registryAddress
        return try await get("/v1/registry/status?registry=\(encodedRegistry)&scheme=\(scheme.rawValue)")
    }

    public func applyRegistry(
        registryAddress: String,
        scheme: RegistryScheme = .https,
        caCertificatePEM: String?,
        caCertificateBase64: String?,
        username: String?,
        password: String?
    ) async throws -> DeviceRegistryApplyResponse {
        try await post("/v1/registry/apply", body: [
            "registry": registryAddress,
            "scheme": scheme.rawValue,
            "ca_certificate_pem": caCertificatePEM ?? "",
            "ca_certificate_base64": caCertificateBase64 ?? "",
            "username": username ?? "",
            "password": password ?? "",
        ])
    }

    public func validateDeviceRegistry(
        registryAddress: String,
        scheme: RegistryScheme = .https,
        image: String? = nil
    ) async throws -> DeviceRegistryValidationResponse {
        try await post("/v1/registry/validate", body: [
            "registry": registryAddress,
            "scheme": scheme.rawValue,
            "image": image ?? "",
        ])
    }

    // MARK: - ROS2 Extended

    public func ros2Launch(package: String, launchFile: String) async throws -> ROS2LaunchResponse {
        try await post("/v1/ros2/launch", body: ["package": package, "launch_file": launchFile])
    }

    public func ros2LaunchStop(pid: Int) async throws -> ROS2LaunchResponse {
        try await post("/v1/ros2/launch/stop", body: ["pid": pid])
    }

    public func ros2Launches() async throws -> ROS2LaunchesResponse {
        try await get("/v1/ros2/launches")
    }

    public func ros2LifecycleNodes() async throws -> ROS2LifecycleNodesResponse {
        try await get("/v1/ros2/lifecycle")
    }

    public func ros2TopicEcho(topic: String) async throws -> ROS2TopicEchoResponse {
        try await post("/v1/ros2/topic/echo", body: ["topic": topic])
    }

    public func ros2BagList() async throws -> ROS2BagListResponse {
        try await get("/v1/ros2/bags")
    }

    public func ros2BagRecord(topics: [String] = [], output: String = "/tmp/thor_bag") async throws -> ROS2LaunchResponse {
        try await post("/v1/ros2/bag/record", body: ["topics": topics, "output": output] as [String: Any])
    }

    public func ros2BagStop(pid: Int) async throws -> ROS2LaunchResponse {
        try await post("/v1/ros2/bag/stop", body: ["pid": pid])
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
