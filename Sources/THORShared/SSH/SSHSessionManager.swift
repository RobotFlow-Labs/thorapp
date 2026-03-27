import Foundation

/// Manages SSH connections to Jetson devices using OpenSSH CLI.
/// Uses ControlMaster sockets for session multiplexing.
public actor SSHSessionManager {
    private var activeSessions: [Int64: SSHSession] = [:]
    private let controlSocketDir: URL

    public init() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("thor-ssh", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.controlSocketDir = tempDir
    }

    // MARK: - Session Lifecycle

    /// Connect to a device via SSH.
    public func connect(
        deviceID: Int64,
        hostname: String,
        username: String,
        port: Int = 22,
        keyPath: String? = nil
    ) async throws -> SSHSession {
        // Close existing session if any
        if let existing = activeSessions[deviceID] {
            await existing.disconnect()
        }

        let controlSocket = controlSocketDir
            .appendingPathComponent("ctrl-\(deviceID).sock").path

        let session = SSHSession(
            deviceID: deviceID,
            hostname: hostname,
            username: username,
            port: port,
            keyPath: keyPath,
            controlSocket: controlSocket
        )

        try await session.connect()
        activeSessions[deviceID] = session
        return session
    }

    /// Disconnect a device session.
    public func disconnect(deviceID: Int64) async {
        if let session = activeSessions.removeValue(forKey: deviceID) {
            await session.disconnect()
        }
    }

    /// Get an active session for a device.
    public func session(for deviceID: Int64) -> SSHSession? {
        activeSessions[deviceID]
    }

    /// Check if a device has an active session.
    public func isConnected(deviceID: Int64) -> Bool {
        activeSessions[deviceID] != nil
    }

    /// Disconnect all sessions.
    public func disconnectAll() async {
        for (_, session) in activeSessions {
            await session.disconnect()
        }
        activeSessions.removeAll()
    }
}

/// Represents a single SSH connection to a Jetson device.
public actor SSHSession {
    public let deviceID: Int64
    public let hostname: String
    public let username: String
    public let port: Int
    private let keyPath: String?
    private let controlSocket: String
    private var controlProcess: Process?
    private var tunnelProcess: Process?

    init(
        deviceID: Int64,
        hostname: String,
        username: String,
        port: Int,
        keyPath: String?,
        controlSocket: String
    ) {
        self.deviceID = deviceID
        self.hostname = hostname
        self.username = username
        self.port = port
        self.keyPath = keyPath
        self.controlSocket = controlSocket
    }

    // MARK: - Connection

    /// Establish the SSH ControlMaster connection.
    func connect() throws {
        var args = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlSocket)",
            "-o", "ControlPersist=600",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", "\(port)",
            "-N",  // no remote command
        ]

        if let keyPath {
            args += ["-i", keyPath]
        }

        args += ["\(username)@\(hostname)"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        try process.run()
        controlProcess = process
    }

    /// Execute a remote command and return output.
    public func execute(_ command: String) async throws -> ProcessResult {
        var args = [
            "-o", "ControlPath=\(controlSocket)",
            "-p", "\(port)",
            "\(username)@\(hostname)",
            command,
        ]

        if let keyPath {
            args = ["-i", keyPath] + args
        }

        return try await runProcess("/usr/bin/ssh", arguments: args)
    }

    /// Open an SSH tunnel to the Jetson agent API.
    public func openTunnel(localPort: Int, remotePort: Int = 8470) throws {
        var args = [
            "-o", "ControlPath=\(controlSocket)",
            "-p", "\(port)",
            "-L", "\(localPort):127.0.0.1:\(remotePort)",
            "-N",
            "\(username)@\(hostname)",
        ]

        if let keyPath {
            args = ["-i", keyPath] + args
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        try process.run()
        tunnelProcess = process
    }

    /// Disconnect and clean up.
    func disconnect() {
        controlProcess?.terminate()
        tunnelProcess?.terminate()
        controlProcess = nil
        tunnelProcess = nil
        try? FileManager.default.removeItem(atPath: controlSocket)
    }

    // MARK: - Process Helper

    private func runProcess(
        _ path: String,
        arguments: [String]
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let result = ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Result of a subprocess execution.
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}
