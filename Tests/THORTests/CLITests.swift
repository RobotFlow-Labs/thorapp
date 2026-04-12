import Foundation
import Testing
@testable import THORShared

@Suite("CLI Integration Tests")
struct CLITests {
    /// Helper to run thorctl and capture output.
    private func runThorctl(_ args: [String]) async throws -> (stdout: String, exitCode: Int32) {
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

    private func thorctlExecutableURL() -> URL? {
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

    private func resolvedProjectRoot() -> String {
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

    @Test("AgentClient health via direct API call")
    func directHealthCheck() async throws {
        let client = AgentClient(port: 8470)
        let health = try await client.health()
        #expect(health.status == "healthy")
        #expect(health.agentVersion == "0.1.0")
    }

    @Test("AgentClient capabilities includes Jetson Thor model")
    func directCapsCheck() async throws {
        let client = AgentClient(port: 8470)
        let caps = try await client.capabilities()
        #expect(caps.hardware.model == "Jetson Thor")
        #expect(caps.hardware.serial == "SIM-THOR-001")
        #expect(caps.hardware.architecture == "aarch64")
    }

    @Test("AgentClient exec runs echo command")
    func directExecCheck() async throws {
        let client = AgentClient(port: 8470)
        let result = try await client.exec(command: "echo thorctl-test-ok")
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("thorctl-test-ok"))
    }

    @Test("AgentClient Docker containers returns response")
    func directDockerCheck() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.dockerContainers()
        #expect(response.containers is [DockerContainer])
    }

    @Test("AgentClient system logs returns response")
    func directLogsCheck() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.systemLogs(lines: 10)
        #expect(response.source == "system")
    }

    @Test("AgentClient services returns response")
    func directServicesCheck() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.services()
        #expect(response.services is [SystemService])
    }

    @Test("thorctl version reports the bundled CLI version")
    func versionSmoke() async throws {
        let result = try await runThorctl(["version"])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("thorctl 0.1.0"))
        #expect(result.stdout.contains("THOR CLI for Jetson device management"))
    }

    @Test("thorctl help exposes the production-facing commands")
    func helpSmoke() async throws {
        let result = try await runThorctl(["help"])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("quickstart [username]"))
        #expect(result.stdout.contains("registry-device-apply"))
        #expect(result.stdout.contains("diagnostics collect"))
        #expect(result.stdout.contains("version"))
    }
}
