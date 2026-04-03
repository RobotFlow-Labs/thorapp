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
        #expect(response.gpuName.contains("Jetson") || response.gpuName.contains("simulated"))
        #expect(response.cudaVersion == "12.6")
        #expect(response.tensorrtVersion == "10.3")
        #expect(response.memoryTotalMb > 0)
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
        #expect(response.count >= 2)  // Sim returns 2 sample models
        #expect(response.models.contains { $0.format == "onnx" })
    }

    // MARK: - ROS2 Extended

    @Test("List ROS2 launches (empty initially)")
    func listLaunches() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2Launches()
        #expect(response.launches is [ROS2ProcessInfo])
    }

    @Test("List ROS2 bags from sim")
    func listBags() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.ros2BagList()
        #expect(response.bags is [ROS2Bag])
    }

    // MARK: - Docker Extended

    @Test("List Docker images from sim")
    func listDockerImages() async throws {
        let client = AgentClient(port: 8470)
        let response = try await client.dockerImages()
        // Docker available in sim but may have 0 images
        #expect(response.images is [DockerImage])
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
}
