import Foundation
import THORShared

/// THORctl — CLI for managing Jetson devices from the terminal.
/// Usage: thorctl <command> [options]

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "help"

@MainActor
func run() async {
    switch command {
    case "devices", "ls":
        await listDevices()
    case "registries":
        await listRegistries()
    case "connect":
        let host = args.count > 2 ? args[2] : "localhost"
        let port = args.count > 3 ? Int(args[3]) ?? 8470 : 8470
        await connectDevice(host: host, port: port)
    case "registry-validate":
        let identifier = args.count > 2 ? args[2] : ""
        await validateRegistry(identifier: identifier)
    case "registry-device-status":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let registry = args.count > 3 ? args[3] : ""
        await registryDeviceStatus(port: port, registry: registry)
    case "registry-device-apply":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let registry = args.count > 3 ? args[3] : ""
        let certPath = args.count > 4 ? args[4] : ""
        let username = args.count > 5 ? args[5] : ""
        let password = args.count > 6 ? args[6] : ""
        await registryDeviceApply(port: port, registry: registry, certPath: certPath, username: username, password: password)
    case "registry-device-preflight":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let registry = args.count > 3 ? args[3] : ""
        let image = args.count > 4 ? args[4] : ""
        await registryDevicePreflight(port: port, registry: registry, image: image)
    case "health":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await checkHealth(port: port)
    case "capabilities", "caps":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await fetchCapabilities(port: port)
    case "metrics":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await fetchMetrics(port: port)
    case "exec":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let cmd = args.count > 3 ? args[3...].joined(separator: " ") : ""
        await execCommand(port: port, command: cmd)
    case "docker":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await dockerStatus(port: port)
    case "anima-modules", "modules":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await listAnimaModules(port: port)
    case "anima-status":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await animaStatus(port: port)
    case "anima-deploy":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let yamlPath = args.count > 3 ? args[3] : ""
        await animaDeploy(port: port, yamlPath: yamlPath)
    case "anima-stop":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let name = args.count > 3 ? args[3] : "default"
        await animaStop(port: port, pipelineName: name)
    case "ros2-nodes":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await ros2Nodes(port: port)
    case "ros2-topics":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await ros2Topics(port: port)
    case "power", "power-mode":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await powerInfo(port: port)
    case "sysinfo":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await systemInfoCmd(port: port)
    case "disks":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await disksCmd(port: port)
    case "cameras":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await camerasCmd(port: port)
    case "gpu":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await gpuCmd(port: port)
    case "usb":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await usbCmd(port: port)
    case "network":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await networkCmd(port: port)
    case "ros2-echo":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let topic = args.count > 3 ? args[3] : "/chatter"
        await ros2EchoCmd(port: port, topic: topic)
    case "screenshot":
        let output = args.count > 2 ? args[2] : "thor-screenshot.png"
        await takeScreenshot(outputPath: output)
    case "watch":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let interval = args.count > 3 ? Int(args[3]) ?? 5 : 5
        await watchMetrics(port: port, interval: interval)
    case "version":
        print("thorctl 0.1.0 — THOR CLI for Jetson device management")
    case "help", "--help", "-h":
        printUsage()
    default:
        print("Unknown command: \(command)")
        printUsage()
    }
}

// MARK: - Commands

func listDevices() async {
    do {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath)
        let devices = try await db.reader.read { dbConn in
            try Device.fetchAll(dbConn)
        }
        if devices.isEmpty {
            print("No devices registered. Add one via the THOR app or 'thorctl connect <host> <port>'.")
            return
        }
        print(String(format: "%-4s %-20s %-25s %-15s %-8s", "ID", "Name", "Hostname", "IP", "Env"))
        print(String(repeating: "-", count: 75))
        for device in devices {
            print(String(format: "%-4d %-20s %-25s %-15s %-8s",
                         device.id ?? 0,
                         String(device.displayName.prefix(20)),
                         String(device.hostname.prefix(25)),
                         String((device.lastKnownIP ?? "—").prefix(15)),
                         device.environment.rawValue))
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func listRegistries() async {
    do {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath)
        let profiles = try await db.reader.read { dbConn in
            try RegistryProfile
                .order(RegistryProfile.Columns.displayName.asc)
                .fetchAll(dbConn)
        }

        if profiles.isEmpty {
            print("No registry profiles saved. Add one via the THOR app.")
            return
        }

        print(String(format: "%-4s %-24s %-32s %-8s", "ID", "NAME", "ENDPOINT", "STATUS"))
        print(String(repeating: "-", count: 78))
        for profile in profiles {
            print(String(format: "%-4d %-24s %-32s %-8s",
                         profile.id ?? 0,
                         String(profile.displayName.prefix(24)),
                         String(profile.endpointLabel.prefix(32)),
                         profile.lastValidationStatus.rawValue))
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func connectDevice(host: String, port: Int) async {
    let client = AgentClient(port: port)
    print("Connecting to \(host):\(port)...")
    do {
        let health = try await client.health()
        print("Connected! Agent v\(health.agentVersion) — \(health.status)")
        let caps = try await client.capabilities()
        print("  Model:    \(caps.hardware.model)")
        print("  Serial:   \(caps.hardware.serial)")
        print("  OS:       \(caps.os.distro)")
        print("  JetPack:  \(caps.jetpackVersion ?? "N/A")")
        print("  Docker:   \(caps.dockerVersion ?? "N/A")")
        print("  ROS2:     \(caps.ros2Available ? "Available" : "Not found")")
        print("  GPU:      \(caps.gpu.name)")
    } catch {
        print("Failed to connect: \(error.localizedDescription)")
    }
}

func checkHealth(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let health = try await client.health()
        print("Status:  \(health.status)")
        print("Agent:   v\(health.agentVersion)")
        print("Time:    \(health.timestamp)")
    } catch {
        print("Unhealthy: \(error.localizedDescription)")
    }
}

func fetchCapabilities(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let caps = try await client.capabilities()
        print("Hardware:")
        print("  Model:        \(caps.hardware.model)")
        print("  Serial:       \(caps.hardware.serial)")
        print("  Architecture: \(caps.hardware.architecture)")
        print("  CPUs:         \(caps.hardware.cpuCount)")
        print("  Memory:       \(caps.hardware.memoryTotalMb) MB")
        print("OS:")
        print("  Distro:       \(caps.os.distro)")
        print("  Kernel:       \(caps.os.release)")
        print("Software:")
        print("  JetPack:      \(caps.jetpackVersion ?? "N/A")")
        print("  Docker:       \(caps.dockerVersion ?? "N/A")")
        print("  ROS2:         \(caps.ros2Available ? "Available" : "Not found")")
        print("GPU:")
        print("  Name:         \(caps.gpu.name)")
        print("  Memory:       \(caps.gpu.memoryTotalMb) MB")
        print("Disk:")
        print("  Total:        \(caps.disk.totalGb) GB")
        print("  Free:         \(caps.disk.freeGb ?? 0) GB")
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func fetchMetrics(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let m = try await client.metrics()
        print("CPU:    \(String(format: "%.1f%%", m.cpu.percent)) — load: \(m.cpu.loadAvg.map { String(format: "%.2f", $0) }.joined(separator: " "))")
        print("Memory: \(m.memory.usedMb)/\(m.memory.totalMb) MB (\(String(format: "%.0f%%", m.memory.percent)))")
        print("Disk:   \(String(format: "%.1f", m.disk.usedGb))/\(String(format: "%.1f", m.disk.totalGb)) GB (\(String(format: "%.0f%%", m.disk.percent)))")
        if !m.temperatures.isEmpty {
            print("Temps:  \(m.temperatures.map { "\($0.key): \(String(format: "%.0f", $0.value))°C" }.joined(separator: ", "))")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func execCommand(port: Int, command: String) async {
    guard !command.isEmpty else {
        print("Usage: thorctl exec <port> <command>")
        return
    }
    let client = AgentClient(port: port)
    do {
        let result = try await client.exec(command: command)
        if !result.stdout.isEmpty { print(result.stdout) }
        if !result.stderr.isEmpty { print("STDERR: \(result.stderr)") }
        if result.exitCode != 0 { print("Exit code: \(result.exitCode)") }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func dockerStatus(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.dockerContainers()
        if response.containers.isEmpty {
            print("No Docker containers found.")
            return
        }
        print(String(format: "%-15s %-30s %-12s %-30s", "NAME", "IMAGE", "STATE", "STATUS"))
        print(String(repeating: "-", count: 90))
        for c in response.containers {
            print(String(format: "%-15s %-30s %-12s %-30s",
                         String(c.name.prefix(15)),
                         String(c.image.prefix(30)),
                         c.state,
                         String(c.status.prefix(30))))
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func listAnimaModules(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.animaModules()
        if response.modules.isEmpty {
            print("No ANIMA modules found.")
            return
        }
        print("ANIMA Modules (\(response.count)):")
        print(String(repeating: "-", count: 80))
        for mod in response.modules {
            let caps = mod.capabilities.map(\.type).joined(separator: ", ")
            let platforms = mod.hardwarePlatforms.map(\.name).joined(separator: ", ")
            print("  \(mod.displayName) v\(mod.version)")
            print("    Category:    \(mod.category)")
            print("    Capabilities: \(caps)")
            print("    Platforms:   \(platforms)")
            print("    Image:       \(mod.containerImage)")
            print()
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func animaStatus(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.animaStatus()
        if response.pipelines.isEmpty {
            print("No ANIMA pipelines deployed.")
            return
        }
        for pipeline in response.pipelines {
            print("Pipeline: \(pipeline.name) — \(pipeline.status)")
            if let containers = pipeline.containers {
                for c in containers {
                    print("  [\(c.State ?? "?")] \(c.Service ?? c.Name ?? "unknown")")
                }
            }
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func animaDeploy(port: Int, yamlPath: String) async {
    guard !yamlPath.isEmpty else {
        print("Usage: thorctl anima-deploy <port> <compose.yaml>")
        return
    }
    do {
        let yaml = try String(contentsOfFile: yamlPath, encoding: .utf8)
        let client = AgentClient(port: port)
        let response = try await client.animaDeploy(composeYAML: yaml)
        print("Deploy: \(response.status)")
        if let out = response.stdout, !out.isEmpty { print(out) }
        if let err = response.stderr, !err.isEmpty { print("STDERR: \(err)") }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func animaStop(port: Int, pipelineName: String) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.animaStop(pipelineName: pipelineName)
        print("Stop: \(response.status)")
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func ros2Nodes(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.ros2Nodes()
        if response.nodes.isEmpty {
            print(response.error ?? "No ROS2 nodes found.")
            return
        }
        print("ROS2 Nodes (\(response.count)):")
        for node in response.nodes { print("  \(node)") }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func ros2Topics(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.ros2Topics()
        if response.topics.isEmpty {
            print(response.error ?? "No ROS2 topics found.")
            return
        }
        print("ROS2 Topics (\(response.count)):")
        for topic in response.topics { print("  \(topic.name) [\(topic.type)]") }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func validateRegistry(identifier: String) async {
    guard !identifier.isEmpty else {
        print("Usage: thorctl registry-validate <id|name|host>")
        return
    }

    do {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath)
        let profiles = try await db.reader.read { dbConn in
            try RegistryProfile.fetchAll(dbConn)
        }

        guard let profile = profiles.first(where: { profile in
            if let id = profile.id, String(id) == identifier {
                return true
            }
            return profile.displayName.caseInsensitiveCompare(identifier) == .orderedSame
                || profile.host.caseInsensitiveCompare(identifier) == .orderedSame
                || profile.endpointLabel.caseInsensitiveCompare(identifier) == .orderedSame
        }) else {
            print("Registry profile not found: \(identifier)")
            return
        }

        let keychain = KeychainManager()
        let password = profile.id.flatMap { keychain.registryPassword(for: $0) }
        let validator = RegistryValidationService()
        let report = await validator.validate(profile: profile, password: password)

        if let profileID = profile.id {
            try await db.writer.write { [report, profileID] dbConn in
                guard var record = try RegistryProfile.fetchOne(dbConn, id: profileID) else { return }
                record.lastValidatedAt = Date()
                record.lastValidationStatus = report.status
                record.lastValidationMessage = report.summary
                record.updatedAt = Date()
                try record.update(dbConn)
            }
        }

        print("Registry: \(report.endpoint)")
        print("Status:   \(report.status.rawValue)")
        print(String(repeating: "-", count: 60))
        for stage in report.stages {
            print("[\(stage.status.rawValue.uppercased())] \(stage.name): \(stage.message)")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func registryDeviceStatus(port: Int, registry: String) async {
    guard !registry.isEmpty else {
        print("Usage: thorctl registry-device-status <port> <registry>")
        return
    }

    let client = AgentClient(port: port)
    do {
        let response = try await client.deviceRegistryStatus(registryAddress: registry)
        print("Registry:       \(response.registry)")
        print("Trusted:        \(response.trusted ? "yes" : "no")")
        print("Authenticated:  \(response.authenticated ? "yes" : "no")")
        print("Ready:          \(response.ready ? "yes" : "no")")
        if let certificatePath = response.certificatePath {
            print("Certificate:    \(certificatePath)")
        }
        print("Message:        \(response.message)")
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func registryDeviceApply(port: Int, registry: String, certPath: String, username: String, password: String) async {
    guard !registry.isEmpty else {
        print("Usage: thorctl registry-device-apply <port> <registry> <cert-path|-> [username] [password]")
        return
    }

    let certificatePEM: String?
    if certPath.isEmpty || certPath == "-" {
        certificatePEM = nil
    } else {
        do {
            certificatePEM = try String(contentsOfFile: certPath, encoding: .utf8)
        } catch {
            print("Error reading certificate: \(error.localizedDescription)")
            return
        }
    }

    let client = AgentClient(port: port)
    do {
        let response = try await client.applyRegistry(
            registryAddress: registry,
            caCertificatePEM: certificatePEM,
            caCertificateBase64: certificatePEM?.data(using: .utf8)?.base64EncodedString(),
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
        print("Registry:       \(response.registry)")
        print("Trusted:        \(response.trusted ? "yes" : "no")")
        print("Authenticated:  \(response.authenticated ? "yes" : "no")")
        print("Ready:          \(response.ready ? "yes" : "no")")
        if !response.stdout.isEmpty {
            print("STDOUT:         \(response.stdout)")
        }
        if !response.stderr.isEmpty {
            print("STDERR:         \(response.stderr)")
        }
        print("Message:        \(response.message)")
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func registryDevicePreflight(port: Int, registry: String, image: String) async {
    guard !registry.isEmpty else {
        print("Usage: thorctl registry-device-preflight <port> <registry> [image]")
        return
    }

    let client = AgentClient(port: port)
    do {
        let response = try await client.validateDeviceRegistry(
            registryAddress: registry,
            image: image.isEmpty ? nil : image
        )
        print("Registry: \(response.registry)")
        print("Status:   \(response.status.rawValue)")
        print("Ready:    \(response.ready ? "yes" : "no")")
        print(String(repeating: "-", count: 60))
        for stage in response.stages {
            print("[\(stage.status.rawValue.uppercased())] \(stage.name): \(stage.message)")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

// MARK: - New Jetson Control Commands

func powerInfo(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let pm = try await client.powerMode()
        let fan = try await client.fanStatus()
        let clocks = try await client.powerClocks()
        print("Power Mode: \(pm.currentMode)")
        if let modes = pm.modes {
            for mode in modes {
                let marker = mode.modeId == pm.currentMode ? ">>>" : "   "
                print("  \(marker) [\(mode.modeId)] \(mode.name)")
            }
        }
        print("Clocks:     \(clocks.enabled ? "LOCKED (max performance)" : "Dynamic")")
        print("Fan:        \(Int(fan.speedPercent))% (PWM: \(fan.currentPwm)/255)")
    } catch { print("Error: \(error.localizedDescription)") }
}

func systemInfoCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let s = try await client.systemInfo()
        print("Model:      \(s.model)")
        print("Hostname:   \(s.hostname)")
        print("OS:         \(s.osRelease)")
        print("Kernel:     \(s.kernel)")
        print("Arch:       \(s.architecture)")
        print("JetPack:    \(s.l4tVersion ?? "N/A")")
        print("Uptime:     \(s.uptime)")
    } catch { print("Error: \(error.localizedDescription)") }
}

func disksCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let d = try await client.disks()
        print(String(format: "%-20s %-8s %-8s %-8s %s", "MOUNT", "SIZE", "USED", "AVAIL", "USE%"))
        for fs in d.filesystems {
            print(String(format: "%-20s %-8s %-8s %-8s %s", fs.mount, fs.size, fs.used, fs.available, fs.percent))
        }
    } catch { print("Error: \(error.localizedDescription)") }
}

func camerasCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let c = try await client.cameras()
        print("Cameras (\(c.count)):")
        for cam in c.cameras {
            print("  [\(cam.type)] \(cam.name) — \(cam.device)")
        }
    } catch { print("Error: \(error.localizedDescription)") }
}

func gpuCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let g = try await client.gpuDetail()
        print("GPU:        \(g.gpuName)")
        print("CUDA:       \(g.cudaVersion ?? "N/A")")
        print("TensorRT:   \(g.tensorrtVersion ?? "N/A")")
        print("Memory:     \(g.memoryUsedMb)/\(g.memoryTotalMb) MB")
        print("Temp:       \(Int(g.temperatureC))°C")
        print("Power:      \(String(format: "%.1f", g.powerDrawW)) W")
        let m = try await client.modelList()
        if m.count > 0 {
            print("Models (\(m.count)):")
            for model in m.models { print("  [\(model.format)] \(model.name)") }
        }
    } catch { print("Error: \(error.localizedDescription)") }
}

func usbCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let u = try await client.usbDevices()
        print("USB Devices (\(u.count)):")
        for dev in u.devices { print("  \(dev.vendorProduct) \(dev.description)") }
    } catch { print("Error: \(error.localizedDescription)") }
}

func networkCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let n = try await client.networkInterfaces()
        print(String(format: "%-12s %-6s %-18s %s", "IFACE", "STATE", "IP", "MAC"))
        for iface in n.interfaces {
            let ip = iface.addresses?.first { $0.family == "inet" }?.address ?? "—"
            print(String(format: "%-12s %-6s %-18s %s", iface.name, iface.state ?? "?", ip, iface.mac ?? ""))
        }
    } catch { print("Error: \(error.localizedDescription)") }
}

func ros2EchoCmd(port: Int, topic: String) async {
    let client = AgentClient(port: port)
    do {
        let r = try await client.ros2TopicEcho(topic: topic)
        if let msg = r.message, !msg.isEmpty {
            print(msg)
        } else {
            print(r.error ?? "No message received")
        }
    } catch { print("Error: \(error.localizedDescription)") }
}

// MARK: - Screenshot

func takeScreenshot(outputPath: String) async {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", outputPath]  // -x = no sound

    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            let fullPath = FileManager.default.currentDirectoryPath + "/" + outputPath
            print("Screenshot saved: \(fullPath)")
        } else {
            print("Screenshot failed (exit \(process.terminationStatus))")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

// MARK: - Watch (live metrics)

func watchMetrics(port: Int, interval: Int) async {
    let client = AgentClient(port: port)
    print("Watching metrics on port \(port) every \(interval)s (Ctrl+C to stop)")
    print(String(repeating: "-", count: 70))

    while !Task.isCancelled {
        do {
            let m = try await client.metrics()
            let line = String(format: "CPU: %5.1f%%  MEM: %4d/%4d MB (%4.0f%%)  DISK: %5.1f/%5.1f GB  LOAD: %s",
                              m.cpu.percent,
                              m.memory.usedMb, m.memory.totalMb, m.memory.percent,
                              m.disk.usedGb, m.disk.totalGb,
                              m.cpu.loadAvg.map { String(format: "%.2f", $0) }.joined(separator: " "))
            print("\(timestamp()) \(line)")
        } catch {
            print("\(timestamp()) Error: \(error.localizedDescription)")
        }
        try? await Task.sleep(for: .seconds(interval))
    }
}

private func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

// MARK: - Help

func printUsage() {
    print("""
    thorctl — THOR CLI for Jetson device management

    USAGE:
      thorctl <command> [port] [args...]

    DEVICE COMMANDS:
      devices, ls                   List registered devices
      registries                    List saved OCI registry profiles
      connect <host> [port]         Connect and show device info
      registry-validate <id|name|host>  Validate a saved OCI registry profile
      registry-device-status <port> <registry>   Show registry trust/auth state on a Jetson
      registry-device-apply <port> <registry> <cert-path|-> [username] [password]
                                   Apply registry trust/auth to a Jetson
      registry-device-preflight <port> <registry> [image]
                                   Validate device-side registry readiness
      health [port]                 Check agent health
      capabilities, caps [port]     Show device capabilities
      metrics [port]                Show system metrics
      exec <port> <command>         Execute command on device
      docker [port]                 List Docker containers

    ANIMA COMMANDS:
      anima-modules, modules [port]           List ANIMA modules
      anima-status [port]                     Show pipeline status
      anima-deploy <port> <compose.yaml>      Deploy ANIMA pipeline
      anima-stop <port> [pipeline-name]       Stop ANIMA pipeline

    ROS2 COMMANDS:
      ros2-nodes [port]             List ROS2 nodes
      ros2-topics [port]            List ROS2 topics

    MONITORING:
      watch [port] [interval]       Live metrics dashboard (default: 5s interval)
      screenshot [filename]         Capture macOS screenshot for debugging

    OTHER:
      version                       Show version
      help                          Show this help

    Default agent port: 8470
    """)
}

// MARK: - Entry Point

Task { @MainActor in
    await run()
    exit(0)
}
dispatchMain()
