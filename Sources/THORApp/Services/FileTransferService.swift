import Foundation
import THORShared

/// Orchestrates file transfers between Mac and Jetson via rsync/scp.
@MainActor
final class FileTransferService {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Sync a local directory to a remote path using rsync over SSH.
    func syncDirectory(
        deviceID: Int64,
        localPath: String,
        remotePath: String,
        port: Int = 2222,
        username: String? = nil,
        hostname: String = "localhost",
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> TransferResult {
        let (resolvedUsername, identityPath) = await sshCredentials(for: deviceID, username: username)
        let safePort = try validatedPort(port)
        let safeUsername = try validatedRemoteUser(resolvedUsername)
        let safeHostname = try validatedRemoteHost(hostname)
        let destination = try remoteDestination(username: safeUsername, hostname: safeHostname, remotePath: remotePath)
        let sshCmd = sshTransportCommand(port: safePort, identityPath: identityPath)

        let args = [
            "-avz", "--progress", "--delete",
            "-e", sshCmd,
            localPath.hasSuffix("/") ? localPath : localPath + "/",
            destination
        ]

        progress(TransferProgress(phase: .starting, percent: 0, message: "Starting rsync..."))

        let result = try await runTransferProcess(
            "/usr/bin/rsync",
            arguments: args,
            progress: progress
        )

        // Record transfer in DB
        if let db = appState.db {
            // Create a job for the transfer
            let job = Job(
                deviceID: deviceID,
                jobType: .fileSync,
                status: result.exitCode == 0 ? .success : .failed,
                startedAt: result.startedAt,
                finishedAt: Date(),
                errorCode: result.exitCode == 0 ? nil : "rsync_\(result.exitCode)",
                errorSummary: result.exitCode == 0 ? nil : result.stderr
            )
            try await db.writer.write { [job] dbConn in
                let record = job
                try record.insert(dbConn)
            }
        }

        return result
    }

    /// Upload a single file via scp.
    func uploadFile(
        deviceID: Int64,
        localPath: String,
        remotePath: String,
        port: Int = 2222,
        username: String? = nil,
        hostname: String = "localhost",
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> TransferResult {
        let (resolvedUsername, identityPath) = await sshCredentials(for: deviceID, username: username)
        let safePort = try validatedPort(port)
        let safeUsername = try validatedRemoteUser(resolvedUsername)
        let safeHostname = try validatedRemoteHost(hostname)
        let destination = try remoteDestination(username: safeUsername, hostname: safeHostname, remotePath: remotePath)

        var args = [
            "-P", "\(safePort)",
            "-o", "StrictHostKeyChecking=accept-new",
        ]
        if let identityPath, !identityPath.isEmpty {
            args += ["-i", identityPath]
        }
        args += [localPath, destination]

        progress(TransferProgress(phase: .starting, percent: 0, message: "Uploading..."))

        let result = try await runTransferProcess(
            "/usr/bin/scp",
            arguments: args,
            progress: progress
        )

        // Record
        if let db = appState.db {
            let job = Job(
                deviceID: deviceID,
                jobType: .fileUpload,
                status: result.exitCode == 0 ? .success : .failed,
                startedAt: result.startedAt,
                finishedAt: Date(),
                errorCode: result.exitCode == 0 ? nil : "scp_\(result.exitCode)",
                errorSummary: result.exitCode == 0 ? nil : result.stderr
            )
            try await db.writer.write { [job] dbConn in
                let record = job
                try record.insert(dbConn)
            }
        }

        return result
    }

    /// Verify a transferred file by comparing checksums.
    func verifyTransfer(
        deviceID: Int64,
        localPath: String,
        remotePath: String,
        port: Int = 2222,
        username: String? = nil,
        hostname: String = "localhost"
    ) async throws -> Bool {
        let (resolvedUsername, identityPath) = await sshCredentials(for: deviceID, username: username)
        let safePort = try validatedPort(port)
        let safeUsername = try validatedRemoteUser(resolvedUsername)
        let safeHostname = try validatedRemoteHost(hostname)
        let quotedRemotePath = try shellQuotedRemotePath(remotePath)

        // Compute local checksum
        let localProcess = Process()
        localProcess.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        localProcess.arguments = ["-a", "256", localPath]
        let localPipe = Pipe()
        localProcess.standardOutput = localPipe
        try localProcess.run()
        localProcess.waitUntilExit()
        let localData = localPipe.fileHandleForReading.readDataToEndOfFile()
        let localHash = String(data: localData, encoding: .utf8)?.components(separatedBy: " ").first ?? ""

        // Compute remote checksum via SSH
        let sshProcess = Process()
        sshProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var sshArguments = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", "\(safePort)",
        ]
        if let identityPath, !identityPath.isEmpty {
            sshArguments += ["-i", identityPath]
        }
        sshArguments += [
            "\(safeUsername)@\(safeHostname)",
            "sha256sum -- \(quotedRemotePath) 2>/dev/null | cut -d' ' -f1",
        ]
        sshProcess.arguments = sshArguments
        let remotePipe = Pipe()
        sshProcess.standardOutput = remotePipe
        try sshProcess.run()
        sshProcess.waitUntilExit()
        let remoteData = remotePipe.fileHandleForReading.readDataToEndOfFile()
        let remoteHash = (String(data: remoteData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let verified = !localHash.isEmpty && localHash == remoteHash

        // Update DB record
        if let db = appState.db {
            try await db.writer.write { [deviceID, localHash, verified] dbConn in
                try TransferRecord
                    .filter(Column("deviceID") == deviceID)
                    .order(Column("createdAt").desc)
                    .limit(1)
                    .fetchAll(dbConn)
                    .forEach { var record = $0
                        record.verified = verified
                        record.checksum = localHash
                        try record.update(dbConn)
                    }
            }
        }

        return verified
    }

    // MARK: - Process Runner

    private func runTransferProcess(
        _ path: String,
        arguments: [String],
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> TransferResult {
        let startedAt = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        progress(TransferProgress(phase: .transferring, percent: 0, message: "Running..."))

        try process.run()
        process.waitUntilExit()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            progress(TransferProgress(phase: .completed, percent: 100, message: "Transfer complete"))
        } else {
            progress(TransferProgress(phase: .failed, percent: 0, message: errStr))
        }

        return TransferResult(
            exitCode: process.terminationStatus,
            stdout: outStr,
            stderr: errStr,
            startedAt: startedAt
        )
    }

    private func validatedPort(_ port: Int) throws -> Int {
        guard (1...65_535).contains(port) else {
            throw FileTransferServiceError.invalidPort(port)
        }
        return port
    }

    private func validatedRemoteUser(_ username: String) throws -> String {
        guard username.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw FileTransferServiceError.invalidRemoteUser(username)
        }
        return username
    }

    private func validatedRemoteHost(_ hostname: String) throws -> String {
        guard hostname.range(of: #"^[A-Za-z0-9.\-:\[\]]+$"#, options: .regularExpression) != nil else {
            throw FileTransferServiceError.invalidRemoteHost(hostname)
        }
        return hostname
    }

    private func remoteDestination(username: String, hostname: String, remotePath: String) throws -> String {
        let quotedPath = try shellQuotedRemotePath(remotePath)
        return "\(username)@\(hostname):\(quotedPath)"
    }

    private func sshCredentials(for deviceID: Int64, username: String?) async -> (String, String?) {
        let config = await appState.deviceConfig(for: deviceID)
        return (username ?? config.sshUsername, appState.keychain.sshKeyPath(for: deviceID))
    }

    private func sshTransportCommand(port: Int, identityPath: String?) -> String {
        var components = ["ssh", "-p", "\(port)", "-o", "StrictHostKeyChecking=accept-new"]
        if let identityPath, !identityPath.isEmpty {
            components += ["-i", shellQuotedArgument(identityPath)]
        }
        return components.joined(separator: " ")
    }

    private func shellQuotedRemotePath(_ remotePath: String) throws -> String {
        guard !remotePath.isEmpty, !remotePath.contains("\0"), !remotePath.contains("\n"), !remotePath.contains("\r") else {
            throw FileTransferServiceError.invalidRemotePath
        }
        return shellQuotedArgument(remotePath)
    }

    private func shellQuotedArgument(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

// MARK: - Transfer Types

struct TransferProgress: Sendable {
    let phase: TransferPhase
    let percent: Int
    let message: String
}

enum TransferPhase: Sendable {
    case starting
    case transferring
    case verifying
    case completed
    case failed
}

struct TransferResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let startedAt: Date
}

enum FileTransferServiceError: LocalizedError {
    case invalidPort(Int)
    case invalidRemoteUser(String)
    case invalidRemoteHost(String)
    case invalidRemotePath

    var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            "Invalid SSH port: \(port)"
        case .invalidRemoteUser(let username):
            "Invalid remote username: \(username)"
        case .invalidRemoteHost(let hostname):
            "Invalid remote hostname: \(hostname)"
        case .invalidRemotePath:
            "Invalid remote path"
        }
    }
}
