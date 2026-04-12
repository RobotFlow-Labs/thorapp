import Foundation
import THORShared

/// Installs or upgrades the THOR agent on a Jetson device via SSH.
@MainActor
final class AgentInstaller {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func install(on device: Device, agentPackagePath: String? = nil) async throws -> InstallResult {
        guard let deviceID = device.id else {
            throw AgentInstallerError.noDeviceID
        }

        let config = await appState.deviceConfig(for: deviceID)
        let username = config.sshUsername
        let sshHost = device.hostname
        let sshPort = (sshHost == "localhost" || sshHost == "127.0.0.1") ? 2222 : config.sshPort
        let identityPath = appState.keychain.sshKeyPath(for: deviceID)

        let healthCheck = try await sshExec(
            host: sshHost,
            port: sshPort,
            username: username,
            identityPath: identityPath,
            command: "curl -fsS http://127.0.0.1:8470/v1/health 2>/dev/null || echo NOT_RUNNING",
            allowFailure: true
        )

        if healthCheck.contains("\"healthy\"") || healthCheck.contains("healthy") {
            return InstallResult(status: .alreadyInstalled, message: "Agent is already running and healthy")
        }

        let agentSourceDir = try resolveAgentSourceDirectory(overridePath: agentPackagePath)
        let remoteUploadDir = "/tmp/thor-agent-upload"
        let remoteInstallDir = "/opt/thor-agent"

        try await scpCopy(
            localPath: agentSourceDir,
            remotePath: remoteUploadDir,
            host: sshHost,
            port: sshPort,
            username: username,
            identityPath: identityPath
        )

        let installCommand = """
        set -euo pipefail
        sudo mkdir -p \(shellQuoted(remoteInstallDir))
        sudo rm -rf \(shellQuoted(remoteInstallDir))/*
        sudo cp -R \(shellQuoted(remoteUploadDir))/. \(shellQuoted(remoteInstallDir))/
        sudo chown -R \(shellQuoted(username)) \(shellQuoted(remoteInstallDir))
        if ! /usr/bin/python3 -m pip --version >/dev/null 2>&1; then
          sudo apt-get update
          sudo apt-get install -y python3-pip
        fi
        /usr/bin/python3 -m pip install --user fastapi 'uvicorn[standard]' psutil
        echo INSTALL_OK
        """

        let installResult = try await sshExec(
            host: sshHost,
            port: sshPort,
            username: username,
            identityPath: identityPath,
            command: installCommand
        )

        guard installResult.contains("INSTALL_OK") else {
            throw AgentInstallerError.installFailed(installResult)
        }

        let serviceUnit = """
        [Unit]
        Description=THOR Jetson Agent
        After=network.target

        [Service]
        Type=simple
        User=\(username)
        WorkingDirectory=\(remoteInstallDir)
        ExecStart=/usr/bin/python3 \(remoteInstallDir)/main.py
        Restart=always
        RestartSec=5
        Environment=THOR_AGENT_HOST=127.0.0.1
        Environment=THOR_AGENT_PORT=8470

        [Install]
        WantedBy=multi-user.target
        """

        let serviceCommand = """
        set -euo pipefail
        cat <<'EOF' | sudo tee /etc/systemd/system/thor-agent.service >/dev/null
        \(serviceUnit)
        EOF
        sudo systemctl daemon-reload
        sudo systemctl enable thor-agent
        sudo systemctl restart thor-agent
        echo SERVICE_OK
        """

        let serviceResult = try await sshExec(
            host: sshHost,
            port: sshPort,
            username: username,
            identityPath: identityPath,
            command: serviceCommand
        )

        guard serviceResult.contains("SERVICE_OK") else {
            throw AgentInstallerError.serviceFailed(serviceResult)
        }

        if let db = appState.db {
            let job = Job(deviceID: deviceID, jobType: .agentInstall, status: .success)
            try await db.writer.write { [job] dbConn in
                let record = job
                try record.insert(dbConn)
            }
        }

        return InstallResult(status: .installed, message: "Agent installed and service started")
    }

    func checkVersion(on device: Device) async throws -> String? {
        guard let deviceID = device.id else {
            throw AgentInstallerError.noDeviceID
        }

        let config = await appState.deviceConfig(for: deviceID)
        let sshHost = device.hostname
        let sshPort = (sshHost == "localhost" || sshHost == "127.0.0.1") ? 2222 : config.sshPort
        let identityPath = appState.keychain.sshKeyPath(for: deviceID)

        let result = try await sshExec(
            host: sshHost,
            port: sshPort,
            username: config.sshUsername,
            identityPath: identityPath,
            command: "curl -fsS http://127.0.0.1:8470/v1/health | /usr/bin/python3 -c \"import json,sys; print(json.load(sys.stdin).get('agent_version', 'unknown'))\"",
            allowFailure: true
        )

        let version = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty || version == "unknown" ? nil : version
    }

    private func resolveAgentSourceDirectory(overridePath: String?) throws -> String {
        let candidates = [
            overridePath,
            Bundle.main.resourcePath.map { $0 + "/Agent" },
            ProcessInfo.processInfo.environment["THOR_AGENT_DIR"],
            FileManager.default.currentDirectoryPath + "/Agent",
        ]

        for candidate in candidates.compactMap({ $0 }) {
            let mainPath = candidate + "/main.py"
            if FileManager.default.fileExists(atPath: mainPath) {
                return candidate
            }
        }

        throw AgentInstallerError.agentSourceMissing
    }

    private func scpCopy(
        localPath: String,
        remotePath: String,
        host: String,
        port: Int,
        username: String,
        identityPath: String?
    ) async throws {
        var arguments = [
            "-r",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            "-P", "\(port)",
        ]
        if let identityPath, !identityPath.isEmpty {
            arguments += ["-i", identityPath]
        }
        arguments += [localPath, "\(username)@\(host):\(remotePath)"]

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw AgentInstallerError.installFailed(output.isEmpty ? "scp exited with \(process.terminationStatus)" : output)
        }
    }

    private func sshExec(
        host: String,
        port: Int,
        username: String,
        identityPath: String?,
        command: String,
        allowFailure: Bool = false
    ) async throws -> String {
        var arguments = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            "-p", "\(port)",
        ]
        if let identityPath, !identityPath.isEmpty {
            arguments += ["-i", identityPath]
        }
        arguments += ["\(username)@\(host)", command]

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if process.terminationStatus != 0, !allowFailure {
            throw AgentInstallerError.commandFailed(output.isEmpty ? "ssh exited with \(process.terminationStatus)" : output)
        }

        return output
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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
    case agentSourceMissing
    case installFailed(String)
    case serviceFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDeviceID:
            return "No device ID"
        case .agentSourceMissing:
            return "THOR agent sources were not found in the app bundle or local repo."
        case .installFailed(let message):
            return "Install failed: \(message)"
        case .serviceFailed(let message):
            return "Service setup failed: \(message)"
        case .commandFailed(let message):
            return "SSH command failed: \(message)"
        }
    }
}
