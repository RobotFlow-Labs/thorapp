import Testing
import Foundation
@testable import THORShared

@Suite("ANIMA Tests")
struct ANIMATests {

    // MARK: - Agent Integration (requires Docker sim on port 8470)

    @Test("Fetch ANIMA modules from agent")
    func fetchModules() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.animaModules()

        #expect(response.count >= 3)
        #expect(response.modules.contains { $0.name == "petra" })
        #expect(response.modules.contains { $0.name == "chronos" })
        #expect(response.modules.contains { $0.name == "pygmalion" })
    }

    @Test("PETRA module has correct manifest structure")
    func petraManifest() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.animaModules()
        let petra = try #require(response.modules.first { $0.name == "petra" })

        #expect(petra.displayName == "PETRA")
        #expect(petra.version == "0.1.0")
        #expect(petra.category == "perception.depth")
        #expect(petra.containerImage.contains("anima-petra"))
        #expect(!petra.capabilities.isEmpty)
        #expect(petra.capabilities[0].type == "depth_prediction")
        #expect(!petra.inputs.isEmpty)
        #expect(!petra.outputs.isEmpty)
        #expect(!petra.hardwarePlatforms.isEmpty)
        #expect(petra.healthTopic == "/anima/petra/health")
    }

    @Test("Module compatibility check for Jetson")
    func moduleCompatibility() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.animaModules()
        let petra = try #require(response.modules.first { $0.name == "petra" })

        #expect(petra.supportsJetson(.thor))
        #expect(petra.supportsJetson(.generic))
        #expect(petra.preferredBackend(for: .thor) == "tensorrt")
    }

    @Test("Pipeline composer generates valid YAML")
    func pipelineComposition() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.animaModules()
        let modules = Array(response.modules.prefix(2))

        let composer = PipelineComposer()
        let yaml = composer.compose(modules: modules, platform: .thor)

        #expect(yaml.contains("version:"))
        #expect(yaml.contains("services:"))
        #expect(yaml.contains("anima-net"))
        #expect(yaml.contains("tensorrt"))
        #expect(yaml.contains("ghcr.io/aiflowlabs"))

        for module in modules {
            #expect(yaml.contains(module.name.lowercased()))
            #expect(yaml.contains(module.containerImage))
        }
    }

    @Test("Pipeline validation catches incompatible modules")
    func pipelineValidation() async throws {
        let incompatible = ANIMAModuleManifest(
            schemaVersion: "1.0",
            name: "test-incompat",
            version: "0.1.0",
            displayName: "Test",
            description: "Test module",
            category: "test",
            containerImage: "test:latest",
            capabilities: [ModuleCapability(type: "test", subtype: nil)],
            inputs: [],
            outputs: [],
            hardwarePlatforms: [PlatformSupport(name: "linux_x86_only", backends: ["cpu"])],
            performanceProfiles: [],
            failureMode: nil,
            timeoutMs: nil,
            healthTopic: nil
        )

        let composer = PipelineComposer()
        let issues = composer.validateCompatibility(modules: [incompatible], platform: .thor)

        #expect(!issues.isEmpty)
        #expect(issues.contains { $0.severity == .error })
    }

    @Test("Fetch ANIMA pipeline status from agent")
    func fetchPipelineStatus() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.animaStatus()

        // Should return (possibly empty) pipeline list without error
        #expect(response.pipelines is [AnimaPipelineStatus])
    }

    // MARK: - JetPack Compatibility

    @Test("JetPack version info lookup")
    func jetpackInfo() {
        let info61 = JetPackCompatibility.jetpackInfo("6.1")
        #expect(info61.cudaVersion == "12.6")
        #expect(info61.tensorrtVersion == "10.3")

        let info60 = JetPackCompatibility.jetpackInfo("6.0")
        #expect(info60.cudaVersion == "12.2")

        let infoUnknown = JetPackCompatibility.jetpackInfo("99.0")
        #expect(infoUnknown.cudaVersion == nil)
    }

    @Test("JetPack compatibility check")
    func jetpackCompatibility() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.animaModules()
        let petra = try #require(response.modules.first { $0.name == "petra" })

        let result = JetPackCompatibility.check(
            module: petra,
            jetpackVersion: "6.1",
            gpuMemoryMB: 8192
        )
        #expect(result.isCompatible)
    }

    // MARK: - ROS2 Introspection

    @Test("Fetch ROS2 nodes from agent (live talker running)")
    func ros2Nodes() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2Nodes()
        // With demo talker running, we should find /talker node
        #expect(response.count >= 1)
        #expect(response.nodes.contains("/talker"))
    }

    @Test("Fetch ROS2 topics from agent (live /chatter topic)")
    func ros2Topics() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2Topics()
        // With demo talker running, /chatter should exist
        #expect(response.count >= 1)
        #expect(response.topics.contains { $0.name == "/chatter" })
    }
}
