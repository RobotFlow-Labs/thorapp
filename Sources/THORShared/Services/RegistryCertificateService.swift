import CryptoKit
import Foundation

public enum RegistryTrustState: Sendable, Equatable {
    case trusted
    case untrusted(reason: String?)
    case missing
}

public struct RegistryCertificateInfo: Sendable {
    public let commonName: String?
    public let subjectSummary: String
    public let issuerSummary: String?
    public let fingerprintSHA256: String
    public let fingerprintSHA1: String
    public let notValidBefore: Date?
    public let notValidAfter: Date?

    public init(
        commonName: String?,
        subjectSummary: String,
        issuerSummary: String?,
        fingerprintSHA256: String,
        fingerprintSHA1: String,
        notValidBefore: Date?,
        notValidAfter: Date?
    ) {
        self.commonName = commonName
        self.subjectSummary = subjectSummary
        self.issuerSummary = issuerSummary
        self.fingerprintSHA256 = fingerprintSHA256
        self.fingerprintSHA1 = fingerprintSHA1
        self.notValidBefore = notValidBefore
        self.notValidAfter = notValidAfter
    }
}

public struct ManagedRegistryCertificate: Sendable {
    public let url: URL
    public let info: RegistryCertificateInfo

    public init(url: URL, info: RegistryCertificateInfo) {
        self.url = url
        self.info = info
    }
}

public enum RegistryCertificateError: Error, LocalizedError {
    case invalidCertificate
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            return "The selected file is not a valid X.509 certificate."
        case .commandFailed(let message):
            return message
        }
    }
}

public struct RegistryCertificateService: Sendable {
    public init() {}

    public func importCertificate(from sourceURL: URL, preferredName: String) throws -> ManagedRegistryCertificate {
        let info = try parseCertificate(at: sourceURL)
        let ext = sourceURL.pathExtension.isEmpty ? "crt" : sourceURL.pathExtension
        let managedURL = Self.certificatesDirectory.appendingPathComponent("\(sanitize(preferredName)).\(ext)")
        try FileManager.default.createDirectory(at: Self.certificatesDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: managedURL.path) {
            try FileManager.default.removeItem(at: managedURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: managedURL)
        return ManagedRegistryCertificate(url: managedURL, info: info)
    }

    public func parseCertificate(at url: URL) throws -> RegistryCertificateInfo {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw RegistryCertificateError.invalidCertificate
        }

        let subjectLine = try runProcess("/usr/bin/openssl", arguments: ["x509", "-in", url.path, "-noout", "-subject"])
        let issuerLine = try runProcess("/usr/bin/openssl", arguments: ["x509", "-in", url.path, "-noout", "-issuer"])
        let datesOutput = try runProcess("/usr/bin/openssl", arguments: ["x509", "-in", url.path, "-noout", "-dates"])

        let subjectSummary = parseOpenSSLDisplayLine(subjectLine, prefix: "subject=")
        let commonName = parseOpenSSLNameLine(subjectLine, prefix: "subject=")
            .first(where: { $0.key == "CN" })?
            .value
        let issuerSummary = parseOpenSSLDisplayLine(issuerLine, prefix: "issuer=")

        let notValidBefore = datesOutput
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("notBefore=") })
            .flatMap { parseOpenSSLDate(String($0.replacingOccurrences(of: "notBefore=", with: ""))) }
        let notValidAfter = datesOutput
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("notAfter=") })
            .flatMap { parseOpenSSLDate(String($0.replacingOccurrences(of: "notAfter=", with: ""))) }

        return RegistryCertificateInfo(
            commonName: commonName,
            subjectSummary: subjectSummary.isEmpty ? "Unknown Subject" : subjectSummary,
            issuerSummary: issuerSummary.isEmpty ? nil : issuerSummary,
            fingerprintSHA256: hexDigest(of: data, using: SHA256.self),
            fingerprintSHA1: hexDigest(of: data, using: Insecure.SHA1.self),
            notValidBefore: notValidBefore,
            notValidAfter: notValidAfter
        )
    }

    public func trustState(for certificateURL: URL?) -> RegistryTrustState {
        guard let certificateURL, FileManager.default.fileExists(atPath: certificateURL.path) else {
            return .missing
        }
        do {
            _ = try runProcess(
                "/usr/bin/security",
                arguments: ["verify-cert", "-c", certificateURL.path, "-k", Self.loginKeychainPath]
            )
            return .trusted
        } catch {
            return .untrusted(reason: error.localizedDescription)
        }
    }

    public func installTrust(for certificateURL: URL) throws {
        _ = try runProcess(
            "/usr/bin/security",
            arguments: [
                "add-trusted-cert",
                "-d",
                "-r", "trustRoot",
                "-k", Self.loginKeychainPath,
                certificateURL.path,
            ]
        )
    }

    public func removeTrust(sha1Fingerprint: String) throws {
        _ = try runProcess(
            "/usr/bin/security",
            arguments: [
                "delete-certificate",
                "-Z", sha1Fingerprint,
                Self.loginKeychainPath,
            ]
        )
    }

    public func removeManagedCertificate(at path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    public static var certificatesDirectory: URL {
        let base = URL(fileURLWithPath: DatabaseManager.defaultPath).deletingLastPathComponent()
        return base.appendingPathComponent("RegistryCertificates", isDirectory: true)
    }

    public static var loginKeychainPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Keychains/login.keychain-db")
            .path
    }

    private func runProcess(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RegistryCertificateError.commandFailed(message.isEmpty ? "\(executable) failed." : message)
        }
        return output
    }

    private func sanitize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: #"[^a-z0-9\-._]+"#, with: "-", options: .regularExpression)
    }

    private func parseOpenSSLDisplayLine(_ line: String, prefix: String) -> String {
        line.replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseOpenSSLNameLine(_ line: String, prefix: String) -> [(key: String, value: String)] {
        parseOpenSSLDisplayLine(line, prefix: prefix)
            .split(separator: ",")
            .compactMap { segment in
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (
                    parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
    }

    private func parseOpenSSLDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        return formatter.date(from: value)
    }

    private func hexDigest<Hash>(of data: Data, using: Hash.Type) -> String where Hash: HashFunction {
        Hash.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }
}
