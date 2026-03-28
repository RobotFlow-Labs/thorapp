import Testing
import Foundation
@testable import THORShared

@Suite("CLI Integration Tests")
struct CLITests {

    /// Helper to run thorctl and capture output.
    private func runThorctl(_ args: [String]) async throws -> (stdout: String, exitCode: Int32) {
        let process = Process()
        // Use swift run to invoke thorctl
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")

        let projectRoot = ProcessInfo.processInfo.environment["THOR_PROJECT_ROOT"]
            ?? FileManager.default.currentDirectoryPath
                .components(separatedBy: ".build").first?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? ""

        process.arguments = ["run", "--package-path", "/\(projectRoot)", "thorctl"] + args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (output, process.terminationStatus)
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
        // May have containers or not, but shouldn't throw
        #expect(response.containers is [DockerContainer])
    }

    @Test("AgentClient system logs returns response")
    func directLogsCheck() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.systemLogs(lines: 10)
        // May have logs or error about journalctl, but shouldn't crash
        #expect(response.source == "system")
    }

    @Test("AgentClient services returns response")
    func directServicesCheck() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.services()
        #expect(response.services is [SystemService])
    }
}
