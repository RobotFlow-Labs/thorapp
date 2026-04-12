import Testing
@testable import THORShared

@Suite
struct CLILiveIntegrationTests {
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
        #expect(response.error == nil)
        #expect(response.containers.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
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
        #expect(response.error == nil)
        #expect(response.services.allSatisfy { !$0.name.isEmpty })
    }
}
