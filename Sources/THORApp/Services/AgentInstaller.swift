import Foundation
import THORShared

/// Installs or upgrades the THOR agent on a Jetson device via SSH.
@MainActor
final class AgentInstaller {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Install the agent on a device.
    func install(on device: Device, agentPackagePath: String? = nil) async throws -> InstallResult {
        guard let deviceID = device.id else {
            throw AgentInstallerError.noDeviceID
        }

        let sshHost = device.hostname
        let sshPort = (sshHost == "localhost" || sshHost == "127.0.0.1") ? 2222 : 22

        // Step 1: Check if agent is already running
        let checkResult = try await sshExec(
            host: sshHost, port: sshPort,
            command: "curl -s http://127.0.0.1:8470/v1/health 2>/dev/null || echo NOT_RUNNING"
        )

        if checkResult.contains("healthy") {
            return InstallResult(status: .alreadyInstalled, message: "Agent is already running and healthy")
        }

        // Step 2: Copy agent package
        let agentDir = "/opt/thor-agent"
        let installCommands = """
        sudo mkdir -p \(agentDir) && \
        sudo chown $(whoami) \(agentDir) && \
        pip3 install --user fastapi 'uvicorn[standard]' psutil 2>/dev/null || \
        pip3 install fastapi 'uvicorn[standard]' psutil && \
        echo "INSTALL_OK"
        """

        let installResult = try await sshExec(
            host: sshHost, port: sshPort,
            command: installCommands
        )

        if !installResult.contains("INSTALL_OK") {
            throw AgentInstallerError.installFailed(installResult)
        }

        // Step 3: Create systemd service
        let serviceUnit = """
        [Unit]
        Description=THOR Jetson Agent
        After=network.target

        [Service]
        Type=simple
        User=jetson
        ExecStart=/usr/bin/python3 \(agentDir)/main.py
        Restart=always
        RestartSec=5
        Environment=THOR_AGENT_HOST=127.0.0.1
        Environment=THOR_AGENT_PORT=8470

        [Install]
        WantedBy=multi-user.target
        """

        let serviceInstall = """
        echo '\(serviceUnit)' | sudo tee /etc/systemd/system/thor-agent.service > /dev/null && \
        sudo systemctl daemon-reload && \
        sudo systemctl enable thor-agent && \
        sudo systemctl start thor-agent && \
        echo "SERVICE_OK"
        """

        let serviceResult = try await sshExec(
            host: sshHost, port: sshPort,
            command: serviceInstall
        )

        if serviceResult.contains("SERVICE_OK") {
            // Record job
            if let db = appState.db {
                let job = Job(deviceID: deviceID, jobType: .agentInstall, status: .success)
                try await db.writer.write { [job] dbConn in
                    var record = job
                    try record.insert(dbConn)
                }
            }
            return InstallResult(status: .installed, message: "Agent installed and service started")
        } else {
            throw AgentInstallerError.serviceFailed(serviceResult)
        }
    }

    /// Check the agent version on a device.
    func checkVersion(on device: Device) async throws -> String? {
        let sshHost = device.hostname
        let sshPort = (sshHost == "localhost" || sshHost == "127.0.0.1") ? 2222 : 22

        let result = try await sshExec(
            host: sshHost, port: sshPort,
            command: "curl -s http://127.0.0.1:8470/v1/health 2>/dev/null | python3 -c \"import sys,json; print(json.load(sys.stdin).get('agent_version','unknown'))\" 2>/dev/null || echo unknown"
        )
        let version = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return version == "unknown" ? nil : version
    }

    private func sshExec(host: String, port: Int, command: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            "-p", "\(port)",
            "jetson@\(host)",
            command,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct InstallResult: Sendable {
    let status: InstallStatus
    let message: String
}

enum InstallStatus: Sendable {
    case installed
    case alreadyInstalled
    case upgraded
}

enum AgentInstallerError: Error, LocalizedError {
    case noDeviceID
    case installFailed(String)
    case serviceFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDeviceID: "No device ID"
        case .installFailed(let msg): "Install failed: \(msg)"
        case .serviceFailed(let msg): "Service setup failed: \(msg)"
        }
    }
}
