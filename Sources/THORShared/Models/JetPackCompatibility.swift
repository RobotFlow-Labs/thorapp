import Foundation

/// JetPack version compatibility matrix for ANIMA modules.
public struct JetPackCompatibility: Sendable {

    /// Check if a module is compatible with the device's JetPack version and GPU.
    public static func check(
        module: ANIMAModuleManifest,
        jetpackVersion: String?,
        gpuMemoryMB: Int
    ) -> CompatibilityResult {
        // Check platform support
        let supportedPlatforms = module.hardwarePlatforms.map(\.name)
        let hasJetsonSupport = supportedPlatforms.contains { name in
            name.lowercased().contains("jetson")
        }
        if !hasJetsonSupport {
            return .incompatible(reason: "Module does not support Jetson platforms")
        }

        // Check JetPack version
        if let jp = jetpackVersion {
            let major = jp.components(separatedBy: ".").first.flatMap(Int.init) ?? 0
            if major < 5 {
                return .incompatible(reason: "Requires JetPack 5.0+ (found \(jp))")
            }
        }

        // Check GPU memory
        if gpuMemoryMB > 0 {
            if let profile = module.performanceProfiles.first(where: { $0.platform.contains("jetson") }),
               let requiredMB = profile.memoryMb, requiredMB > gpuMemoryMB {
                return .incompatible(reason: "Requires \(requiredMB) MB GPU memory (available: \(gpuMemoryMB) MB)")
            }
        }

        // Check backend availability
        let jetsonPlatform = module.hardwarePlatforms.first { $0.name.contains("jetson") }
        let backends = jetsonPlatform?.backends ?? []
        let hasTensorRT = backends.contains("tensorrt")
        let hasCUDA = backends.contains("cuda")

        if hasTensorRT {
            return .compatible(backend: "tensorrt", notes: "TensorRT acceleration available")
        }
        if hasCUDA {
            return .compatible(backend: "cuda", notes: "CUDA backend")
        }
        return .compatible(backend: "cpu", notes: "CPU fallback — may be slow")
    }

    /// Known JetPack version info.
    public static func jetpackInfo(_ version: String?) -> JetPackInfo {
        guard let v = version else {
            return JetPackInfo(version: "Unknown", cudaVersion: nil, tensorrtVersion: nil, l4tVersion: nil)
        }
        // Known mappings
        switch v {
        case let v where v.hasPrefix("6.1"):
            return JetPackInfo(version: v, cudaVersion: "12.6", tensorrtVersion: "10.3", l4tVersion: "36.4")
        case let v where v.hasPrefix("6.0"):
            return JetPackInfo(version: v, cudaVersion: "12.2", tensorrtVersion: "8.6", l4tVersion: "36.3")
        case let v where v.hasPrefix("5.1"):
            return JetPackInfo(version: v, cudaVersion: "11.4", tensorrtVersion: "8.5", l4tVersion: "35.4")
        case let v where v.hasPrefix("5.0"):
            return JetPackInfo(version: v, cudaVersion: "11.4", tensorrtVersion: "8.4", l4tVersion: "35.1")
        default:
            return JetPackInfo(version: v, cudaVersion: nil, tensorrtVersion: nil, l4tVersion: nil)
        }
    }
}

public enum CompatibilityResult: Sendable {
    case compatible(backend: String, notes: String)
    case incompatible(reason: String)
    case unknown

    public var isCompatible: Bool {
        if case .compatible = self { return true }
        return false
    }
}

public struct JetPackInfo: Sendable {
    public let version: String
    public let cudaVersion: String?
    public let tensorrtVersion: String?
    public let l4tVersion: String?
}
