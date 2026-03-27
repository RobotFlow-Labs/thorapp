import Testing
import Foundation
@testable import THORShared

@Suite("Agent Client Tests")
struct AgentClientTests {

    /// Integration test — requires Docker Jetson sim running on port 8470.
    /// Run: docker compose up -d
    @Test("Fetch health from running agent")
    func fetchHealth() async throws {
        let client = AgentClient(port: 8470)
        let health = try await client.health()

        #expect(health.isHealthy)
        #expect(health.agentVersion == "0.1.0")
        #expect(health.status == "healthy")
    }

    @Test("Fetch capabilities from running agent")
    func fetchCapabilities() async throws {
        let client = AgentClient(port: 8470)
        let caps = try await client.capabilities()

        #expect(caps.hardware.model == "Jetson Thor")
        #expect(caps.hardware.serial == "SIM-THOR-001")
        #expect(caps.hardware.architecture == "aarch64")
        #expect(caps.os.distro.contains("Ubuntu"))
        #expect(caps.jetpackVersion == "6.1")
        #expect(caps.agentVersion == "0.1.0")
    }

    @Test("Fetch metrics from running agent")
    func fetchMetrics() async throws {
        let client = AgentClient(port: 8470)
        let metrics = try await client.metrics()

        #expect(metrics.cpu.percent >= 0)
        #expect(metrics.memory.totalMb > 0)
        #expect(metrics.disk.totalGb > 0)
        #expect(!metrics.cpu.loadAvg.isEmpty)
    }

    @Test("Execute safe command on agent")
    func execCommand() async throws {
        let client = AgentClient(port: 8470)
        let result: AgentExecResponse = try await client.exec(command: "echo hello-thor")

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("hello-thor"))
    }
}
