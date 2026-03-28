import Foundation

/// Discovers Jetson devices on the local network using mDNS/Bonjour.
@MainActor
final class NetworkDiscovery {
    var discoveredDevices: [DiscoveredDevice] = []
    var isScanning = false

    /// Scan the local network for Jetson candidates.
    func scan() async {
        isScanning = true
        discoveredDevices = []

        // Strategy 1: mDNS — look for _ssh._tcp services
        await scanMDNS()

        // Strategy 2: ARP table scan for known Jetson MAC prefixes
        await scanARPTable()

        isScanning = false
    }

    private func scanMDNS() async {
        // Use dns-sd to browse for SSH services
        let result = await runProcess(
            "/usr/bin/dns-sd",
            arguments: ["-B", "_ssh._tcp.", "local."],
            timeout: 5
        )

        guard let output = result else { return }

        // Parse dns-sd output for hostnames
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // dns-sd output: "Timestamp  A/R  Flags  if  Domain  Service Type  Instance Name"
            if trimmed.lowercased().contains("jetson") ||
               trimmed.lowercased().contains("nvidia") ||
               trimmed.lowercased().contains("tegra") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if let name = parts.last {
                    discoveredDevices.append(DiscoveredDevice(
                        hostname: name + ".local",
                        displayName: name,
                        source: .mdns
                    ))
                }
            }
        }
    }

    private func scanARPTable() async {
        let result = await runProcess("/usr/sbin/arp", arguments: ["-a"], timeout: 5)
        guard let output = result else { return }

        // NVIDIA Jetson MAC prefixes (48:b0:2d is common for Jetson)
        let jetsonPrefixes = ["48:b0:2d", "00:04:4b"]

        for line in output.components(separatedBy: "\n") {
            let lower = line.lowercased()
            for prefix in jetsonPrefixes {
                if lower.contains(prefix) {
                    // Extract IP: arp -a format is "? (IP) at MAC on iface"
                    if let ipRange = line.range(of: #"\([\d.]+\)"#, options: .regularExpression) {
                        let ip = String(line[ipRange]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                        // Avoid duplicates
                        if !discoveredDevices.contains(where: { $0.hostname == ip }) {
                            discoveredDevices.append(DiscoveredDevice(
                                hostname: ip,
                                displayName: "Jetson (\(ip))",
                                source: .arp
                            ))
                        }
                    }
                }
            }
        }
    }

    private func runProcess(_ path: String, arguments: [String], timeout: TimeInterval) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()

            // Wait with timeout
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            if process.isRunning {
                process.terminate()
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

struct DiscoveredDevice: Identifiable, Sendable {
    let id = UUID()
    let hostname: String
    let displayName: String
    let source: DiscoverySource
}

enum DiscoverySource: String, Sendable {
    case mdns
    case arp
    case manual
}
