import Foundation

/// Captures and verifies SSH host key fingerprints for TOFU (Trust On First Use).
public struct HostKeyVerifier: Sendable {

    public init() {}

    /// Fetch the SSH host key fingerprint from a remote host.
    public func fetchFingerprint(host: String, port: Int = 22) async -> HostKeyResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keyscan")
        process.arguments = ["-p", "\(port)", "-t", "ed25519,rsa", host]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let scanData = stdout.fileHandleForReading.readDataToEndOfFile()
            let scanOutput = String(data: scanData, encoding: .utf8) ?? ""

            guard !scanOutput.isEmpty else {
                return .unreachable
            }

            // Now compute the fingerprint
            let fingerprintProcess = Process()
            fingerprintProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            fingerprintProcess.arguments = ["-l", "-f", "-"]

            let fpStdin = Pipe()
            let fpStdout = Pipe()
            fingerprintProcess.standardInput = fpStdin
            fingerprintProcess.standardOutput = fpStdout

            try fingerprintProcess.run()
            fpStdin.fileHandleForWriting.write(scanData)
            fpStdin.fileHandleForWriting.closeFile()
            fingerprintProcess.waitUntilExit()

            let fpData = fpStdout.fileHandleForReading.readDataToEndOfFile()
            let fpOutput = String(data: fpData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Parse: "256 SHA256:abc123... host (ED25519)"
            let parts = fpOutput.components(separatedBy: " ")
            let fingerprint = parts.count >= 2 ? parts[1] : fpOutput
            let keyType = parts.last?.trimmingCharacters(in: CharacterSet(charactersIn: "()")) ?? "unknown"

            return .success(HostKeyInfo(
                fingerprint: fingerprint,
                keyType: keyType,
                rawKey: scanOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            ))

        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Verify a host key against a stored fingerprint.
    public func verify(
        host: String,
        port: Int,
        storedFingerprint: String
    ) async -> HostKeyVerification {
        let result = await fetchFingerprint(host: host, port: port)

        switch result {
        case .success(let info):
            if info.fingerprint == storedFingerprint {
                return .trusted
            } else {
                return .changed(
                    previous: storedFingerprint,
                    current: info.fingerprint
                )
            }
        case .unreachable:
            return .unreachable
        case .error(let msg):
            return .error(msg)
        }
    }
}

public enum HostKeyResult: Sendable {
    case success(HostKeyInfo)
    case unreachable
    case error(String)
}

public struct HostKeyInfo: Sendable {
    public let fingerprint: String
    public let keyType: String
    public let rawKey: String
}

public enum HostKeyVerification: Sendable {
    case trusted
    case changed(previous: String, current: String)
    case unreachable
    case error(String)

    public var isTrusted: Bool {
        if case .trusted = self { return true }
        return false
    }
}
