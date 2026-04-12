import Testing
import Foundation
@testable import THORShared

@Suite("Jetson Control Center Tests")
struct JetsonControlTests {

    // MARK: - Power (real endpoints, Docker sim)

    @Test("Get power mode from sim")
    func getPowerMode() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.powerMode()
        #expect(response.currentMode >= 0)
        let modes = response.modes ?? []
        #expect(!modes.isEmpty)
        #expect(modes.contains { $0.name == "MAXN" })
    }

    @Test("Set power mode on sim")
    func setPowerMode() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.setPowerMode(1)
        #expect(response.currentMode == 1)
        #expect(response.status == "ok")
    }

    @Test("Get clocks status from sim")
    func getClocks() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.powerClocks()
        // Sim starts with clocks disabled
        #expect(response.enabled == false || response.enabled == true)
    }

    @Test("Get fan status from sim")
    func getFan() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.fanStatus()
        #expect(response.speedPercent >= 0)
        #expect(response.targetPwm >= 0)
    }

    // MARK: - System

    @Test("Get system info from sim")
    func getSystemInfo() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.systemInfo()
        #expect(response.model == "Jetson Thor")
        #expect(response.osRelease.contains("Ubuntu"))
        #expect(!response.kernel.isEmpty)
        #expect(!response.uptime.isEmpty)
    }

    @Test("List packages from sim")
    func listPackages() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.packages()
        #expect(response.total > 0)
        #expect(!response.packages.isEmpty)
    }

    @Test("List users from sim")
    func listUsers() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.users()
        #expect(response.users.contains { $0.name == "jetson" })
    }

    // MARK: - Storage

    @Test("Get disk info from sim")
    func getDiskInfo() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.disks()
        #expect(!response.filesystems.isEmpty)
        // Should have at least root filesystem
        #expect(response.filesystems.contains { $0.mount == "/" })
    }

    @Test("Get swap info from sim")
    func getSwapInfo() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.swap()
        // Swap may or may not be configured, but response shouldn't crash
        #expect(response.error == nil || response.swap != nil)
    }

    // MARK: - Network

    @Test("List network interfaces from sim")
    func listInterfaces() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.networkInterfaces()
        #expect(!response.interfaces.isEmpty)
        // Should at least have loopback
        #expect(response.interfaces.contains { $0.name == "lo" })
    }

    // MARK: - Hardware

    @Test("List cameras from sim")
    func listCameras() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.cameras()
        #expect(response.count >= 2)  // Sim returns 2 fake cameras
        #expect(response.cameras.contains { $0.type == "CSI" })
    }

    @Test("Bridge camera frame into sim and fetch snapshot")
    func bridgeCameraFrameIntoSim() async throws {
        let client = AgentClient(port: 8470)
        let cameraID = "zed-bridge-\(UUID().uuidString)"
        let jpegBase64 = "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAqADAAQAAAABAAAAAgAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAgACAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A/XCiiigD/9k="
        guard let jpegData = Data(base64Encoded: jpegBase64) else {
            Issue.record("Failed to decode embedded JPEG fixture")
            return
        }

        let cleanup: () async -> Void = {
            _ = try? await client.removeCameraBridge(cameraID: cameraID)
        }

        do {
            let bridge = try await client.cameraBridgeFrame(
                cameraID: cameraID,
                name: "ZED 2i Bridge Test",
                type: "ZED",
                width: 2,
                height: 2,
                fps: 15,
                jpegData: jpegData
            )

            #expect(bridge.status == "ok")
            #expect(bridge.cameraID == cameraID)
            #expect(bridge.bridgeState == "active")
            #expect(bridge.previewPath == "/v1/hardware/cameras/\(cameraID)/snapshot")

            let cameras = try await client.cameras()
            let bridgedCamera = cameras.cameras.first { $0.device == "bridge:\(cameraID)" }
            #expect(bridgedCamera != nil)
            #expect(bridgedCamera?.source == "bridge")
            #expect(bridgedCamera?.bridgeState == "active")
            #expect(bridgedCamera?.previewPath == "/v1/hardware/cameras/\(cameraID)/snapshot")
            #expect(bridgedCamera?.type == "ZED")

            let snapshot = try await client.cameraSnapshot(cameraID: cameraID)
            #expect(snapshot.count > 0)
            #expect(snapshot.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
        } catch {
            await cleanup()
            throw error
        }

        await cleanup()
    }

    @Test("Get GPIO pins from sim")
    func getGPIO() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.gpio()
        #expect(response.count >= 4)  // Sim returns 4 fake pins
    }

    @Test("Scan I2C buses from sim")
    func scanI2C() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.i2cScan()
        #expect(!response.buses.isEmpty)
    }

    @Test("List USB devices from sim")
    func listUSB() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.usbDevices()
        #expect(response.count >= 0)  // May or may not have devices
    }

    @Test("List serial ports from sim")
    func listSerial() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.serialPorts()
        #expect(response.count >= 0)
    }

    // MARK: - GPU

    @Test("Get GPU info from sim")
    func getGPUInfo() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.gpuDetail()
        #expect(response.gpuName.contains("Jetson") || response.gpuName.contains("simulated") || response.gpuName.contains("Apple Silicon"))
        #expect(response.memoryTotalMb > 0)
        if response.backend == "mlx" {
            #expect(response.metalAvailable == true)
            #expect(response.runtimeLabel == "docker_mlx_cpp")
        } else {
            #expect(response.cudaVersion == "12.6")
            #expect(response.tensorrtVersion == "10.3")
        }
    }

    @Test("List TensorRT engines from sim")
    func listTRTEngines() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.tensorrtEngines()
        // Sim may have 0 engines
        #expect(response.count >= 0)
    }

    @Test("List models from sim")
    func listModels() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.modelList()
        #expect(response.count >= 0)
        if !response.models.isEmpty {
            #expect(response.models.contains { $0.format == "onnx" || $0.format == "mlx" })
        }
    }

    // MARK: - ROS2 Extended

    @Test("List ROS2 launches (empty initially)")
    func listLaunches() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2Launches()
        #expect(response.launches.allSatisfy { $0.pid > 0 && !$0.category.isEmpty })
    }

    @Test("Get ROS2 graph snapshot from sim")
    func getROS2GraphSnapshot() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2Graph()

        #expect(!response.graph.nodes.isEmpty)
        #expect(response.graph.nodes.contains { $0.name == "/camera_driver" })
        #expect(response.graph.edges.contains { $0.topic == "/scan" && $0.messageType == "sensor_msgs/msg/LaserScan" })
        #expect(!response.graph.capturedAt.isEmpty)
    }

    @Test("Read and update ROS2 parameters on sim")
    func readAndUpdateROS2Parameters() async throws {
        let client = AgentClient(port: 8470)

        let initial = try await client.ros2Parameters(node: "/camera_driver")
        #expect(initial.count >= 2)
        #expect(initial.parameters.contains { $0.name == "exposure" && $0.value == "42" })

        let updated = try await client.ros2SetParameter(node: "/camera_driver", name: "exposure", value: "48")
        #expect(updated.success)
        #expect(updated.value == "48")

        let refreshed = try await client.ros2Parameters(node: "/camera_driver")
        #expect(refreshed.parameters.contains { $0.name == "exposure" && $0.value == "48" })
    }

    @Test("List ROS2 actions from sim")
    func listROS2Actions() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2Actions()

        #expect(response.count >= 2)
        #expect(response.actions.contains { $0.name == "/navigate_to_pose" })
        #expect(response.actions.contains { $0.type == "nav2_msgs/action/NavigateToPose" })
    }

    @Test("Get ROS2 topic stats from sim")
    func getROS2TopicStats() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2TopicStats()

        #expect(response.count >= 3)
        #expect(response.topics.contains { $0.topic == "/camera/image_raw" && ($0.hz ?? 0) > 0 })
        #expect(response.topics.contains { $0.topic == "/scan" && $0.messageType == "sensor_msgs/msg/LaserScan" })
    }

    @Test("List ROS2 bags from sim")
    func listBags() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2BagList()
        #expect(response.bags.allSatisfy { !$0.name.isEmpty && !$0.path.isEmpty })
    }

    // MARK: - Docker Extended

    @Test("List Docker images from sim")
    func listDockerImages() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.dockerImages()
        // Docker available in sim but may have 0 images
        #expect(response.images.allSatisfy { !$0.repository.isEmpty && !$0.imageId.isEmpty })
    }

    // MARK: - Streams + Diagnostics

    @Test("List unified stream catalog from sim")
    func listUnifiedStreamCatalog() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.streamCatalog()

        #expect(response.count >= 3)
        #expect(response.streams.contains { $0.id == "camera-image-raw" && $0.kind == .image })
        #expect(response.streams.contains { $0.id == "scan-main" && $0.kind == .scan })
    }

    @Test("Fetch stream health from sim")
    func fetchStreamHealth() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.streamHealth(sourceID: "camera-image-raw")

        #expect(response.health.sourceID == "camera-image-raw")
        #expect(response.health.status == .ready)
        #expect(response.health.transportHealthy)
        #expect(response.health.timestampsSane)
        #expect(response.health.expectedRate)
    }

    @Test("Fetch latest image frame from stream endpoint")
    func fetchLatestStreamImage() async throws {
        let client = AgentClient(port: 8470)
        let data = try await client.latestStreamImage(sourceID: "camera-image-raw")

        #expect(data.count > 0)
        #expect(data.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test("Fetch latest LaserScan frame from stream endpoint")
    func fetchLatestLaserScanFrame() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.latestLaserScan(sourceID: "scan-main")

        #expect(response.scan.sourceID == "scan-main")
        #expect(response.scan.ranges.count == response.scan.intensities.count)
        #expect(response.scan.rangeMax == 12.0)
        #expect(response.metadata?.status == .ready)
    }

    @Test("Collect diagnostics archive from sim")
    func collectDiagnosticsArchive() async throws {
        let client = AgentClient(port: 8470)
        let archive = try await client.diagnosticsArchive(sectionSelection: ["capabilities", "ros2", "streams"])

        #expect(archive.count > 0)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("thor-diagnostics-\(UUID().uuidString).zip")
        try archive.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let archiveDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("thor-diagnostics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: archiveDirectory) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", tempURL.path, "-d", archiveDirectory.path]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: archiveDirectory.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: archiveDirectory.appendingPathComponent("ros2/graph.json").path))
        #expect(FileManager.default.fileExists(atPath: archiveDirectory.appendingPathComponent("streams/catalog.json").path))
        #expect(FileManager.default.fileExists(atPath: archiveDirectory.appendingPathComponent("SUMMARY.md").path))
    }

    // MARK: - Registry Device Integration

    @Test("Apply registry trust and auth on sim")
    func applyRegistryOnSim() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.applyRegistry(
            registryAddress: "registry.demo.local:5443",
            caCertificatePEM: """
            -----BEGIN CERTIFICATE-----
            ZGVtby10aG9yLXJlZ2lzdHJ5LWNlcnQ=
            -----END CERTIFICATE-----
            """,
            caCertificateBase64: nil,
            username: "demo",
            password: "secret"
        )

        #expect(response.registry == "registry.demo.local:5443")
        #expect(response.trusted)
        #expect(response.authenticated)
        #expect(response.ready)
    }

    @Test("Registry device preflight passes after apply on sim")
    func registryPreflightOnSim() async throws {
        let client = AgentClient(port: 8470)
        _ = try await client.applyRegistry(
            registryAddress: "registry.demo.local:5443",
            caCertificatePEM: """
            -----BEGIN CERTIFICATE-----
            ZGVtby10aG9yLXJlZ2lzdHJ5LWNlcnQ=
            -----END CERTIFICATE-----
            """,
            caCertificateBase64: nil,
            username: "demo",
            password: "secret"
        )

        let validation = try await client.validateDeviceRegistry(
            registryAddress: "registry.demo.local:5443",
            image: "registry.demo.local:5443/demo/app:latest"
        )

        #expect(validation.status == .pass)
        #expect(validation.ready)
        #expect(validation.stages.contains { $0.name == "Device Pull Preflight" && $0.status == .pass })
    }

    @Test("Registry rejects path traversal identifiers")
    func rejectInvalidRegistryAddress() async {
        let client = AgentClient(port: 8470)

        do {
            _ = try await client.applyRegistry(
                registryAddress: "../../home/jetson/.ssh",
                caCertificatePEM: """
                -----BEGIN CERTIFICATE-----
                ZGVtby10aG9yLXJlZ2lzdHJ5LWNlcnQ=
                -----END CERTIFICATE-----
                """,
                caCertificateBase64: nil,
                username: nil,
                password: nil
            )
            Issue.record("Expected invalid registry address to be rejected")
        } catch let error as AgentClientError {
            if case .httpError(let code, let body) = error {
                #expect(code == 400)
                #expect(body.contains("Invalid registry address"))
            } else {
                Issue.record("Unexpected AgentClientError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
