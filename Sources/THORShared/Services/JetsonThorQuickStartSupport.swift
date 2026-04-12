import Foundation
import Darwin

public enum JetsonThorConsolePortKind: String, Codable, Sendable, CaseIterable {
    case debugUSB = "debug_usb"
    case oemConfig = "oem_config"
}

public struct JetsonThorSerialCandidate: Codable, Sendable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var kind: JetsonThorConsolePortKind
    public var recommended: Bool
    public var baudRate: Int

    public init(
        path: String,
        kind: JetsonThorConsolePortKind,
        recommended: Bool,
        baudRate: Int
    ) {
        self.path = path
        self.kind = kind
        self.recommended = recommended
        self.baudRate = baudRate
    }
}

public struct JetsonThorPublicKeyCandidate: Codable, Sendable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var recommended: Bool

    public init(path: String, recommended: Bool) {
        self.path = path
        self.recommended = recommended
    }
}

public struct JetsonThorHostSnapshot: Codable, Sendable, Equatable {
    public var debugSerialCandidates: [JetsonThorSerialCandidate]
    public var oemConfigCandidates: [JetsonThorSerialCandidate]
    public var publicKeyCandidates: [JetsonThorPublicKeyCandidate]
    public var usbTetherHostAddresses: [String]

    public init(
        debugSerialCandidates: [JetsonThorSerialCandidate] = [],
        oemConfigCandidates: [JetsonThorSerialCandidate] = [],
        publicKeyCandidates: [JetsonThorPublicKeyCandidate] = [],
        usbTetherHostAddresses: [String] = []
    ) {
        self.debugSerialCandidates = debugSerialCandidates
        self.oemConfigCandidates = oemConfigCandidates
        self.publicKeyCandidates = publicKeyCandidates
        self.usbTetherHostAddresses = usbTetherHostAddresses
    }

    public var usbTetherDetected: Bool {
        !usbTetherHostAddresses.isEmpty
    }

    public static let empty = JetsonThorHostSnapshot()
}

public struct JetsonThorQuickStartSupport: Sendable {
    private let devRoot: String
    private let homeDirectory: String
    private let interfaceAddressesOverride: [String]?

    public init(
        devRoot: String = "/dev",
        homeDirectory: String = NSHomeDirectory(),
        interfaceAddressesOverride: [String]? = nil
    ) {
        self.devRoot = devRoot
        self.homeDirectory = homeDirectory
        self.interfaceAddressesOverride = interfaceAddressesOverride
    }

    public func snapshot() -> JetsonThorHostSnapshot {
        let debugPaths = serialPaths(prefix: "cu.usbserial-")
        let oemPaths = serialPaths(prefix: "cu.usbmodem")
        let keyPaths = publicKeyPaths()
        let interfaceAddresses = interfaceAddressesOverride ?? Self.currentIPv4Addresses()

        return JetsonThorHostSnapshot(
            debugSerialCandidates: Self.debugSerialCandidates(from: debugPaths),
            oemConfigCandidates: Self.oemConfigCandidates(from: oemPaths),
            publicKeyCandidates: Self.publicKeyCandidates(from: keyPaths),
            usbTetherHostAddresses: interfaceAddresses.filter(Self.isJetsonUSBTetherAddress)
        )
    }

    public static func debugSerialCandidates(from paths: [String]) -> [JetsonThorSerialCandidate] {
        let recommended = recommendedDebugSerialPath(from: paths)
        return paths.sorted().map { path in
            JetsonThorSerialCandidate(
                path: path,
                kind: .debugUSB,
                recommended: path == recommended,
                baudRate: 9600
            )
        }
    }

    public static func oemConfigCandidates(from paths: [String]) -> [JetsonThorSerialCandidate] {
        let recommended = recommendedOEMConfigPath(from: paths)
        return paths.sorted().map { path in
            JetsonThorSerialCandidate(
                path: path,
                kind: .oemConfig,
                recommended: path == recommended,
                baudRate: 115200
            )
        }
    }

    public static func publicKeyCandidates(from paths: [String]) -> [JetsonThorPublicKeyCandidate] {
        let recommended = recommendedPublicKeyPath(from: paths)
        return paths
            .sorted { lhs, rhs in
                compareKeyPriority(lhs, rhs)
            }
            .map { path in
                JetsonThorPublicKeyCandidate(path: path, recommended: path == recommended)
            }
    }

    public static func recommendedDebugSerialPath(from paths: [String]) -> String? {
        let sorted = paths.sorted()
        if sorted.count >= 2 {
            return sorted[1]
        }
        return sorted.first
    }

    public static func recommendedOEMConfigPath(from paths: [String]) -> String? {
        paths.sorted().first
    }

    public static func recommendedPublicKeyPath(from paths: [String]) -> String? {
        paths.min { compareKeyPriority($0, $1) }
    }

    public static func usbTetherDetected(addresses: [String]) -> Bool {
        addresses.contains(where: isJetsonUSBTetherAddress)
    }

    public static func isJetsonUSBTetherAddress(_ address: String) -> Bool {
        address.hasPrefix("192.168.55.")
    }

    public static func uefiConsoleCommand(serialPath: String) -> String {
        let quotedPath = shellQuoted(serialPath)
        return "printf '\\e[8;61;242t'; if command -v tio >/dev/null 2>&1; then tio -b 9600 \(quotedPath); else screen \(quotedPath) 9600; fi"
    }

    public static func linuxConsoleCommand(serialPath: String) -> String {
        let quotedPath = shellQuoted(serialPath)
        return "if command -v tio >/dev/null 2>&1; then tio -b 115200 \(quotedPath); else screen \(quotedPath) 115200; fi"
    }

    public static func oemConfigConsoleCommand(serialPath: String) -> String {
        linuxConsoleCommand(serialPath: serialPath)
    }

    public static func usbSSHCommand(
        username: String,
        identityPath: String? = nil,
        host: String = "192.168.55.1"
    ) -> String {
        sshCommand(
            username: username,
            host: host,
            identityPath: identityPath,
            remoteCommand: nil
        )
    }

    public static func jetPackInstallCommand(
        username: String,
        identityPath: String? = nil,
        host: String = "192.168.55.1"
    ) -> String {
        sshCommand(
            username: username,
            host: host,
            identityPath: identityPath,
            remoteCommand: "sudo apt update && sudo apt install -y nvidia-jetpack"
        )
    }

    public static func dockerSmokeTestCommand(
        username: String,
        identityPath: String? = nil,
        host: String = "192.168.55.1"
    ) -> String {
        sshCommand(
            username: username,
            host: host,
            identityPath: identityPath,
            remoteCommand: "docker --version && sudo systemctl status docker --no-pager"
        )
    }

    public static func sshKeyGenerationCommand(
        keyPath: String = "$HOME/.ssh/id_ed25519",
        comment: String = "thor-jetson"
    ) -> String {
        let quotedKeyPath = shellQuoted(keyPath)
        let quotedPublicKeyPath = shellQuoted("\(keyPath).pub")
        return "if [ ! -f \(quotedPublicKeyPath) ]; then ssh-keygen -t ed25519 -f \(quotedKeyPath) -C \(shellQuoted(comment)); else echo \"SSH key already exists at \(keyPath)\"; fi"
    }

    public static func bootstrapHelperCommand(
        scriptPath: String,
        target: String,
        publicKeyPath: String?
    ) -> String {
        var command = "/bin/bash \(shellQuoted(scriptPath)) \(shellQuoted(target))"
        if let publicKeyPath, !publicKeyPath.isEmpty {
            command += " \(shellQuoted(publicKeyPath))"
        }
        return command
    }

    public static func sshCommand(
        username: String,
        host: String,
        identityPath: String? = nil,
        remoteCommand: String?
    ) -> String {
        var components: [String] = [
            "ssh",
            "-tt",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        if let identityPath, !identityPath.isEmpty {
            components += ["-i", shellQuoted(identityPath)]
        }
        components.append("\(username)@\(host)")
        if let remoteCommand, !remoteCommand.isEmpty {
            components.append(shellQuoted(remoteCommand))
        }
        return components.joined(separator: " ")
    }

    private func serialPaths(prefix: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: devRoot) else {
            return []
        }
        return entries
            .filter { $0.hasPrefix(prefix) }
            .map { "\(devRoot)/\($0)" }
            .sorted()
    }

    private func publicKeyPaths() -> [String] {
        let sshDirectory = URL(fileURLWithPath: homeDirectory).appendingPathComponent(".ssh")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: sshDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return entries
            .filter { $0.pathExtension == "pub" }
            .map(\.path)
    }

    private static func compareKeyPriority(_ lhs: String, _ rhs: String) -> Bool {
        let lhsScore = keyPriorityScore(for: lhs)
        let rhsScore = keyPriorityScore(for: rhs)
        if lhsScore == rhsScore {
            return lhs < rhs
        }
        return lhsScore < rhsScore
    }

    private static func keyPriorityScore(for path: String) -> Int {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        switch fileName {
        case "id_ed25519.pub":
            return 0
        case let name where name.hasPrefix("thor_jetson_") && name.hasSuffix(".pub"):
            return 1
        case "id_ecdsa.pub":
            return 2
        case "id_rsa.pub":
            return 3
        default:
            return 10
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func currentIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var interfacePointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfacePointer) == 0, let first = interfacePointer else {
            return addresses
        }
        defer { freeifaddrs(interfacePointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            defer { cursor = interface.ifa_next }

            guard let addressPointer = interface.ifa_addr else {
                continue
            }
            guard addressPointer.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addressPointer,
                socklen_t(addressPointer.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let hostnameBytes = hostname.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                addresses.append(String(decoding: hostnameBytes, as: UTF8.self))
            }
        }

        return addresses.sorted()
    }
}
