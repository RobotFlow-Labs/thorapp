import Foundation
import Testing

private enum THORCLITestHarness {
    static func runThorctl(_ args: [String]) async throws -> (stdout: String, exitCode: Int32) {
        let process = Process()
        if let thorctlURL = thorctlExecutableURL() {
            process.executableURL = thorctlURL
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")

            let projectRoot = resolvedProjectRoot()
            process.arguments = ["run", "--package-path", projectRoot, "thorctl"] + args
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (output, process.terminationStatus)
    }

    private static func thorctlExecutableURL() -> URL? {
        let projectRoot = resolvedProjectRoot()

        let candidates = [
            "\(projectRoot)/.build/arm64-apple-macosx/debug/thorctl",
            "\(projectRoot)/.build/debug/thorctl",
            "\(projectRoot)/.build/release/thorctl",
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private static func resolvedProjectRoot() -> String {
        if let projectRoot = ProcessInfo.processInfo.environment["THOR_PROJECT_ROOT"], !projectRoot.isEmpty {
            return projectRoot
        }
        if let root = FileManager.default.currentDirectoryPath
            .components(separatedBy: ".build")
            .first, !root.isEmpty
        {
            return root
        }
        return FileManager.default.currentDirectoryPath
    }
}

@Suite
struct CLISmokeTests {
    @Test("thorctl version reports the bundled CLI version")
    func versionSmoke() async throws {
        let result = try await THORCLITestHarness.runThorctl(["version"])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("thorctl 0.1.0"))
        #expect(result.stdout.contains("THOR CLI for Jetson device management"))
    }

    @Test("thorctl help exposes the production-facing commands")
    func helpSmoke() async throws {
        let result = try await THORCLITestHarness.runThorctl(["help"])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("quickstart [username]"))
        #expect(result.stdout.contains("registry-device-apply"))
        #expect(result.stdout.contains("diagnostics collect"))
        #expect(result.stdout.contains("version"))
    }
}
