import Foundation

// MARK: - Power

public struct PowerModeResponse: Codable, Sendable {
    public let currentMode: Int
    public let modes: [PowerMode]?
    public let status: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case currentMode = "current_mode"
        case modes, status, error
    }
}

public struct PowerMode: Codable, Sendable, Identifiable {
    public var id: Int { self.modeId }
    public let modeId: Int
    public let name: String
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case modeId = "id"
        case name, description
    }
}

public struct PowerClocksResponse: Codable, Sendable {
    public let enabled: Bool
    public let details: String?
    public let status: String?
    public let error: String?
}

public struct FanStatusResponse: Codable, Sendable {
    public let targetPwm: Int
    public let currentPwm: Int
    public let speedPercent: Double
    public let status: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case targetPwm = "target_pwm"
        case currentPwm = "current_pwm"
        case speedPercent = "speed_percent"
        case status, error
    }
}

// MARK: - System

public struct SystemInfoResponse: Codable, Sendable {
    public let kernel: String
    public let kernelVersion: String?
    public let architecture: String
    public let hostname: String
    public let osRelease: String
    public let model: String
    public let tegraRelease: String?
    public let l4tVersion: String?
    public let uptime: String
    public let pythonVersion: String?
    public let timestamp: String

    enum CodingKeys: String, CodingKey {
        case kernel
        case kernelVersion = "kernel_version"
        case architecture, hostname
        case osRelease = "os_release"
        case model
        case tegraRelease = "tegra_release"
        case l4tVersion = "l4t_version"
        case uptime
        case pythonVersion = "python_version"
        case timestamp
    }
}

public struct PackagesResponse: Codable, Sendable {
    public let packages: [InstalledPackage]
    public let total: Int
    public let error: String?
}

public struct InstalledPackage: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let version: String
    public let description: String?
}

public struct PackageActionResponse: Codable, Sendable {
    public let action: String
    public let exitCode: Int?
    public let stdout: String?
    public let stderr: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case action
        case exitCode = "exit_code"
        case stdout, stderr, error
    }
}

public struct UsersResponse: Codable, Sendable {
    public let users: [SystemUser]
}

public struct SystemUser: Codable, Sendable, Identifiable {
    public var id: Int { uid }
    public let name: String
    public let uid: Int
    public let gid: Int
    public let home: String
    public let shell: String
}

// MARK: - Storage

public struct DisksResponse: Codable, Sendable {
    public let blockDevices: [BlockDeviceInfo]?
    public let filesystems: [FilesystemInfo]
    public let nvmeHealth: NVMeHealthInfo?

    enum CodingKeys: String, CodingKey {
        case blockDevices = "block_devices"
        case filesystems
        case nvmeHealth = "nvme_health"
    }
}

public struct BlockDeviceInfo: Codable, Sendable {
    public let name: String?
    public let size: String?
    public let type: String?
    public let mountpoint: String?
    public let fstype: String?
}

public struct FilesystemInfo: Codable, Sendable, Identifiable {
    public var id: String { "\(source)-\(mount)" }
    public let source: String
    public let fstype: String
    public let size: String
    public let used: String
    public let available: String
    public let percent: String
    public let mount: String
}

public struct NVMeHealthInfo: Codable, Sendable {
    public let raw: String?
    public let status: String?
}

public struct SwapResponse: Codable, Sendable {
    public let swap: SwapInfo?
    public let swapFiles: [SwapFile]?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case swap
        case swapFiles = "swap_files"
        case error
    }
}

public struct SwapInfo: Codable, Sendable {
    public let total: String
    public let used: String
    public let free: String
}

public struct SwapFile: Codable, Sendable {
    public let name: String
    public let type: String?
    public let size: String?
}

// MARK: - Network

public struct NetworkInterfacesResponse: Codable, Sendable {
    public let interfaces: [NetworkInterfaceInfo]
    public let error: String?
}

public struct NetworkInterfaceInfo: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let state: String?
    public let mac: String?
    public let mtu: Int?
    public let addresses: [InterfaceAddress]?
}

public struct InterfaceAddress: Codable, Sendable {
    public let family: String?
    public let address: String?
    public let prefix: Int?
}

public struct WifiListResponse: Codable, Sendable {
    public let networks: [WifiNetwork]
    public let error: String?
}

public struct WifiNetwork: Codable, Sendable, Identifiable {
    public var id: String { ssid }
    public let ssid: String
    public let signal: Int
    public let security: String
    public let channel: String?
    public let frequency: String?
}

public struct WifiConnectResponse: Codable, Sendable {
    public let success: Bool
    public let ssid: String?
    public let error: String?
}

// MARK: - Hardware

public struct CameraListResponse: Codable, Sendable {
    public let cameras: [CameraDevice]
    public let count: Int
}

public struct CameraDevice: Codable, Sendable, Identifiable {
    public var id: String { device }
    public let name: String
    public let device: String
    public let type: String
    public let details: String?
}

public struct GPIOResponse: Codable, Sendable {
    public let pins: [GPIOPin]
    public let count: Int
}

public struct GPIOPin: Codable, Sendable, Identifiable {
    public var id: Int { number }
    public let number: Int
    public let direction: String
    public let value: Int
}

public struct I2CResponse: Codable, Sendable {
    public let buses: [I2CBus]
}

public struct I2CBus: Codable, Sendable, Identifiable {
    public var id: Int { bus }
    public let bus: Int
    public let devices: [I2CDevice]
}

public struct I2CDevice: Codable, Sendable {
    public let address: String
    public let status: String
}

public struct USBDevicesResponse: Codable, Sendable {
    public let devices: [USBDevice]
    public let count: Int
}

public struct USBDevice: Codable, Sendable, Identifiable {
    public var id: String { busDevice }
    public let busDevice: String
    public let vendorProduct: String
    public let description: String

    enum CodingKeys: String, CodingKey {
        case busDevice = "bus_device"
        case vendorProduct = "vendor_product"
        case description
    }
}

public struct SerialPortsResponse: Codable, Sendable {
    public let ports: [SerialPort]
    public let count: Int
}

public struct SerialPort: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let type: String
}

// MARK: - GPU

public struct GPUDetailResponse: Codable, Sendable {
    public let gpuName: String
    public let cudaVersion: String?
    public let tensorrtVersion: String?
    public let memoryTotalMb: Int
    public let memoryUsedMb: Int
    public let memoryFreeMb: Int
    public let utilizationPercent: Double
    public let temperatureC: Double
    public let powerDrawW: Double

    enum CodingKeys: String, CodingKey {
        case gpuName = "gpu_name"
        case cudaVersion = "cuda_version"
        case tensorrtVersion = "tensorrt_version"
        case memoryTotalMb = "memory_total_mb"
        case memoryUsedMb = "memory_used_mb"
        case memoryFreeMb = "memory_free_mb"
        case utilizationPercent = "utilization_percent"
        case temperatureC = "temperature_c"
        case powerDrawW = "power_draw_w"
    }
}

public struct TensorRTEnginesResponse: Codable, Sendable {
    public let engines: [TRTEngine]
    public let count: Int
}

public struct TRTEngine: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let sizeBytes: Int
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case name, path
        case sizeBytes = "size_bytes"
        case createdAt = "created_at"
    }
}

public struct ModelListResponse: Codable, Sendable {
    public let models: [ModelFile]
    public let count: Int
}

public struct ModelFile: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let format: String
    public let sizeBytes: Int
    public let lastModified: String

    enum CodingKeys: String, CodingKey {
        case name, path, format
        case sizeBytes = "size_bytes"
        case lastModified = "last_modified"
    }
}

// MARK: - ROS2 Extended

public struct ROS2LaunchResponse: Codable, Sendable {
    public let pid: Int?
    public let status: String
    public let package: String?
    public let launchFile: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case pid, status
        case package = "package"
        case launchFile = "launch_file"
        case error
    }
}

public struct ROS2LaunchesResponse: Codable, Sendable {
    public let launches: [ROS2ProcessInfo]
}

public struct ROS2ProcessInfo: Codable, Sendable, Identifiable {
    public var id: Int { pid }
    public let pid: Int
    public let command: String
    public let category: String
    public let startedAt: String
    public let running: Bool

    enum CodingKeys: String, CodingKey {
        case pid, command, category
        case startedAt = "started_at"
        case running
    }
}

public struct ROS2LifecycleNodesResponse: Codable, Sendable {
    public let nodes: [ROS2LifecycleNode]
    public let error: String?
}

public struct ROS2LifecycleNode: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let state: String
}

public struct ROS2TopicEchoResponse: Codable, Sendable {
    public let topic: String
    public let message: String?
    public let error: String?
}

public struct ROS2BagListResponse: Codable, Sendable {
    public let bags: [ROS2Bag]
    public let recordings: [ROS2ProcessInfo]?
}

public struct ROS2Bag: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let sizeBytes: Int?

    enum CodingKeys: String, CodingKey {
        case name, path
        case sizeBytes = "size_bytes"
    }
}

// MARK: - Docker Extended

public struct DockerImagesResponse: Codable, Sendable {
    public let images: [DockerImage]
    public let error: String?
}

public struct DockerImage: Codable, Sendable, Identifiable {
    public var id: String { imageId }
    public let repository: String
    public let tag: String
    public let imageId: String
    public let size: String
    public let created: String

    enum CodingKeys: String, CodingKey {
        case repository, tag
        case imageId = "id"
        case size, created
    }
}
