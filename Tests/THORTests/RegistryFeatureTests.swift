import Foundation
import Testing
@testable import THORShared

@Suite("Registry Feature Tests")
struct RegistryFeatureTests {
    @Test("Registry profile database round-trip")
    func registryProfileRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)
        let profile = RegistryProfile(
            displayName: "Thor Demo Registry",
            host: "registry.local",
            port: 5443,
            scheme: .https,
            username: "demo",
            repositoryNamespace: "thor/demo",
            caCertificatePath: "/tmp/demo.crt",
            caCertificateFingerprintSHA256: "sha256-demo",
            caCertificateFingerprintSHA1: "sha1-demo",
            caCertificateCommonName: "registry.local",
            caCertificateIssuer: "Thor Test CA",
            lastValidationStatus: .warning,
            lastValidationMessage: "Needs trust"
        )

        try db.writer.write { dbConn in
            try profile.insert(dbConn)
        }

        let saved = try db.reader.read { dbConn in
            try RegistryProfile
                .filter(RegistryProfile.Columns.displayName == "Thor Demo Registry")
                .fetchOne(dbConn)
        }

        #expect(saved != nil)
        #expect(saved?.displayName == "Thor Demo Registry")
        #expect(saved?.host == "registry.local")
        #expect(saved?.port == 5443)
        #expect(saved?.scheme == .https)
        #expect(saved?.username == "demo")
        #expect(saved?.repositoryNamespace == "thor/demo")
        #expect(saved?.lastValidationStatus == .warning)
    }

    @Test("Registry certificate import and parse")
    func registryCertificateImportAndParse() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyURL = tempDir.appendingPathComponent("registry.key")
        let certURL = tempDir.appendingPathComponent("registry.crt")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "req",
            "-x509",
            "-newkey", "rsa:2048",
            "-nodes",
            "-keyout", keyURL.path,
            "-out", certURL.path,
            "-days", "1",
            "-subj", "/CN=thor-registry-test/O=RobotFlow Labs"
        ]

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "openssl failed: \(errorOutput)")

        let certificatesDirectory = tempDir.appendingPathComponent("managed-certs", isDirectory: true)
        let service = RegistryCertificateService(certificatesDirectory: certificatesDirectory)
        let managed = try service.importCertificate(
            from: certURL,
            preferredName: "thor-registry-\(UUID().uuidString)"
        )
        defer { service.removeManagedCertificate(at: managed.url.path) }

        #expect(FileManager.default.fileExists(atPath: managed.url.path))
        #expect(managed.url.path.hasPrefix(certificatesDirectory.path))
        #expect(managed.info.subjectSummary.contains("thor-registry-test"))
        #expect(managed.info.fingerprintSHA256.isEmpty == false)
        #expect(managed.info.fingerprintSHA1.isEmpty == false)
        #expect(managed.info.notValidAfter != nil)
    }

    @Test("Registry validation warns when credentials are incomplete")
    func registryValidationWarnsWithoutPassword() async {
        let profile = RegistryProfile(
            displayName: "Incomplete Auth",
            host: "127.0.0.1",
            port: 8470,
            scheme: .http,
            username: "demo"
        )

        let report = await RegistryValidationService().validate(profile: profile, password: nil)
        let credentialsStage = report.stages.first(where: { $0.name == "Credentials" })

        #expect(credentialsStage != nil)
        #expect(credentialsStage?.status == .warning)
        #expect(report.status.rank >= RegistryValidationStatus.warning.rank)
    }

    @Test("Managed certificate cleanup only removes files inside THOR storage")
    func managedCertificateCleanupStaysScoped() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let certificatesDirectory = tempDir.appendingPathComponent("managed-certs", isDirectory: true)
        let externalFile = tempDir.appendingPathComponent("outside.crt")

        try FileManager.default.createDirectory(at: certificatesDirectory, withIntermediateDirectories: true)
        try Data("external".utf8).write(to: externalFile)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = RegistryCertificateService(certificatesDirectory: certificatesDirectory)
        service.removeManagedCertificate(at: externalFile.path)

        #expect(FileManager.default.fileExists(atPath: externalFile.path))

        let managedFile = certificatesDirectory.appendingPathComponent("inside.crt")
        try Data("managed".utf8).write(to: managedFile)
        service.removeManagedCertificate(at: managedFile.path)

        #expect(FileManager.default.fileExists(atPath: managedFile.path) == false)
    }
}
