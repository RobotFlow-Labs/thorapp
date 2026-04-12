import Testing
import Foundation
@testable import THORShared

@Suite("Pipeline Composer Tests")
struct PipelineComposerTests {

    private func sampleModule(
        name: String = "test-module",
        platform: String = "jetson",
        backends: [String] = ["tensorrt", "cuda"],
        memoryMb: Int? = 512
    ) -> ANIMAModuleManifest {
        ANIMAModuleManifest(
            schemaVersion: "1.0",
            name: name,
            version: "0.1.0",
            displayName: name.uppercased(),
            description: "Test module",
            category: "test",
            containerImage: "ghcr.io/test/\(name):0.1.0",
            capabilities: [ModuleCapability(type: "test_cap", subtype: nil)],
            inputs: [ModuleIO(name: "input", ros2Type: "std_msgs/msg/String", encoding: nil, typicalHz: nil, minHz: 1)],
            outputs: [ModuleIO(name: "output", ros2Type: "std_msgs/msg/String", encoding: nil, typicalHz: 10, minHz: nil)],
            hardwarePlatforms: [PlatformSupport(name: platform, backends: backends)],
            performanceProfiles: [PerformanceProfile(platform: "\(platform)_tensorrt", model: nil, backend: "tensorrt", fps: 30, latencyP50Ms: 35, memoryMb: memoryMb)],
            failureMode: "returns_empty",
            timeoutMs: 5000,
            healthTopic: "/anima/\(name)/health"
        )
    }

    @Test("Compose single module pipeline")
    func composeSingle() {
        let composer = PipelineComposer()
        let module = sampleModule()
        let yaml = composer.compose(modules: [module], platform: .thor)

        #expect(yaml.contains("test-module:"))
        #expect(yaml.contains("image: ghcr.io/test/test-module:0.1.0"))
        #expect(yaml.contains("ANIMA_BACKEND=tensorrt"))
        #expect(yaml.contains("anima-net"))
        #expect(yaml.contains("healthcheck:"))
    }

    @Test("Compose multi-module pipeline")
    func composeMulti() {
        let composer = PipelineComposer()
        let modules = [
            sampleModule(name: "perception"),
            sampleModule(name: "tracking"),
            sampleModule(name: "planning"),
        ]
        let yaml = composer.compose(modules: modules, platform: .thor)

        #expect(yaml.contains("perception:"))
        #expect(yaml.contains("tracking:"))
        #expect(yaml.contains("planning:"))
        // Each gets a different port
        #expect(yaml.contains("8034:8034"))
        #expect(yaml.contains("8035:8034"))
        #expect(yaml.contains("8036:8034"))
    }

    @Test("Validation catches unsupported platform")
    func validateUnsupported() {
        let composer = PipelineComposer()
        let module = sampleModule(platform: "linux_x86_only")
        let issues = composer.validateCompatibility(modules: [module], platform: .thor)

        #expect(issues.contains { $0.severity == .error })
    }

    @Test("Validation warns on GPU memory exceeded")
    func validateGPUMemory() {
        let composer = PipelineComposer()
        let modules = [
            sampleModule(name: "big1", memoryMb: 4096),
            sampleModule(name: "big2", memoryMb: 4096),
        ]
        let issues = composer.validateCompatibility(modules: modules, platform: .thor, gpuMemoryMB: 6000)

        #expect(issues.contains { $0.severity == .warning && $0.message.contains("GPU memory") })
    }

    @Test("Validation warns on duplicate capabilities")
    func validateDuplicateCaps() {
        let composer = PipelineComposer()
        let modules = [
            sampleModule(name: "a"),
            sampleModule(name: "b"),
        ]
        let issues = composer.validateCompatibility(modules: modules, platform: .thor)

        #expect(issues.contains { $0.message.contains("Duplicate capability") })
    }

    @Test("Preferred backend selection")
    func preferredBackend() {
        let module = sampleModule(backends: ["tensorrt", "cuda", "cpu"])
        #expect(module.preferredBackend(for: .thor) == "tensorrt")

        let cudaOnly = sampleModule(backends: ["cuda", "cpu"])
        #expect(cudaOnly.preferredBackend(for: .thor) == "cuda")

        let cpuOnly = sampleModule(backends: ["cpu"])
        #expect(cpuOnly.preferredBackend(for: .thor) == "cpu")
    }

    @Test("JetsonPlatform from model string")
    func platformDetection() {
        #expect(JetsonPlatform.from(model: "NVIDIA Jetson Thor") == .thor)
        #expect(JetsonPlatform.from(model: "Jetson Orin NX 16GB") == .orinNX)
        #expect(JetsonPlatform.from(model: "Jetson AGX Orin") == .agxOrin)
        #expect(JetsonPlatform.from(model: "Some Unknown Board") == .generic)
    }

    @Test("Pipeline DB record round-trip")
    func pipelineRecord() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)

        // Need a device first
        let device = Device(displayName: "Test", hostname: "test.local")
        try db.writer.write { dbConn in
            try device.insert(dbConn)
        }
        let deviceID = try db.reader.read { dbConn in
            try Device.fetchOne(dbConn)!.id!
        }

        // Insert pipeline
        let pipeline = Pipeline(
            name: "test-pipeline",
            description: "A test",
            modules: [sampleModule()],
            deviceID: deviceID,
            status: .draft,
            composeYAML: "version: 3.9\nservices: {}"
        )
        try db.writer.write { dbConn in
            try pipeline.insert(dbConn)
        }

        let fetched = try db.reader.read { dbConn in
            try Pipeline.fetchAll(dbConn)
        }
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "test-pipeline")
        #expect(fetched[0].status == .draft)
        #expect(fetched[0].moduleNames.contains("test-module"))
    }
}
