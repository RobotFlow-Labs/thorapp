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
    case "discover":
        await discoverDevices()
    case "quickstart":
        let username = args.count > 2 ? args[2] : "nvidia"
        quickStart(username: username)
    case "doctor":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await connectionDoctor(port: port)
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
    case "ros2":
        let subcommand = args.count > 2 ? args[2] : "help"
        switch subcommand {
        case "graph":
            let port = args.count > 3 ? Int(args[3]) ?? 8470 : 8470
            await ros2GraphCmd(port: port)
        case "params":
            let port = args.count > 3 ? Int(args[3]) ?? 8470 : 8470
            let node = args.count > 4 ? args[4] : ""
            await ros2ParamsCmd(port: port, node: node)
        case "actions":
            let port = args.count > 3 ? Int(args[3]) ?? 8470 : 8470
            await ros2ActionsCmd(port: port)
        default:
            print("Usage: thorctl ros2 <graph|params|actions> [port] [node]")
        }
    case "streams":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        await streamsCmd(port: port)
    case "stream-stats":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let sourceID = args.count > 3 ? args[3] : nil
        await streamStatsCmd(port: port, sourceID: sourceID)
    case "recipe":
        let subcommand = args.count > 2 ? args[2] : "help"
        switch subcommand {
        case "run":
            let port = args.count > 3 ? Int(args[3]) ?? 8470 : 8470
            let identifier = args.count > 4 ? args[4] : ""
            let overrides = args.count > 5 ? Array(args[5...]) : []
            await recipeRunCmd(port: port, identifier: identifier, overrides: overrides)
        default:
            print("Usage: thorctl recipe run <port> <recipe-id|name> [KEY=VALUE ...]")
        }
    case "diagnostics":
        let subcommand = args.count > 2 ? args[2] : "help"
        switch subcommand {
        case "collect":
            let port = args.count > 3 ? Int(args[3]) ?? 8470 : 8470
            let output = args.count > 4 ? args[4] : "thor-diagnostics-\(Int(Date().timeIntervalSince1970)).zip"
            await diagnosticsCollectCmd(port: port, outputPath: output)
        default:
            print("Usage: thorctl diagnostics collect <port> [output.zip]")
        }
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
    case "camera-snapshot":
        let port = args.count > 2 ? Int(args[2]) ?? 8470 : 8470
        let cameraID = args.count > 3 ? args[3] : ""
        let outputPath = args.count > 4 ? args[4] : "thor-camera-snapshot.jpg"
        await cameraSnapshotCmd(port: port, cameraID: cameraID, outputPath: outputPath)
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

private func padded(_ value: String, width: Int) -> String {
    let truncated = value.count > width ? String(value.prefix(width)) : value
    let padding = max(width - truncated.count, 0)
    return truncated + String(repeating: " ", count: padding)
}

private func tableRow(_ columns: [(String, Int)]) -> String {
    columns.map { padded($0.0, width: $0.1) }.joined(separator: " ")
}

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
        print(tableRow([("ID", 4), ("Name", 20), ("Hostname", 25), ("IP", 15), ("Env", 8)]))
        print(String(repeating: "-", count: 75))
        for device in devices {
            print(tableRow([
                ("\(device.id ?? 0)", 4),
                (device.displayName, 20),
                (device.hostname, 25),
                (device.lastKnownIP ?? "—", 15),
                (device.environment.rawValue, 8),
            ]))
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func discoverDevices() async {
    print("Discovering THOR-ready devices...")
    print(String(repeating: "-", count: 72))

    await listDevices()
    print("")
    print("Simulator probe:")

    for port in [8470, 8471] {
        let client = AgentClient(port: port)
        do {
            let health = try await client.health()
            let capabilities = try await client.capabilities()
            print("  [FOUND] localhost:\(port) — \(capabilities.hardware.model) — agent \(health.agentVersion)")
        } catch {
            print("  [MISS ] localhost:\(port) — \(error.localizedDescription)")
        }
    }
}

func connectionDoctor(port: Int) async {
    let client = AgentClient(port: port)
    print("THOR Connection Doctor — port \(port)")
    print(String(repeating: "-", count: 60))

    do {
        let health = try await client.health()
        let capabilities = try await client.capabilities()
        let dockerReady = capabilities.dockerVersion != nil
        let rosReady = capabilities.ros2Available

        print("[PASS] Reachability: Agent reachable")
        print("[PASS] Health: \(health.status) (agent v\(health.agentVersion))")
        print("[INFO] JetPack: \(capabilities.jetpackVersion ?? "unknown")")
        print("[\(dockerReady ? "PASS" : "WARN")] Docker: \(capabilities.dockerVersion ?? "not detected")")
        print("[\(rosReady ? "PASS" : "WARN")] ROS2: \(rosReady ? "available" : "missing")")
        print("[INFO] GPU: \(capabilities.gpu.name)")
        print("[INFO] Disk Free: \(capabilities.disk.freeGb ?? 0) GB")
    } catch {
        let message = error.localizedDescription.lowercased()
        if message.contains("refused") || message.contains("timed out") || message.contains("could not connect") {
            print("[FAIL] Reachability: host unreachable or agent port closed")
            print("Next action: verify THOR agent is running and the tunnel/port is reachable.")
        } else if message.contains("401") || message.contains("403") {
            print("[FAIL] Authentication: access denied")
            print("Next action: refresh SSH credentials or agent trust state.")
        } else {
            print("[FAIL] Unknown: \(error.localizedDescription)")
            print("Next action: collect diagnostics and inspect raw agent logs.")
        }
    }
}

func quickStart(username: String) {
    let support = JetsonThorQuickStartSupport()
    let snapshot = support.snapshot()
    let resolvedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "nvidia" : username

    print("Jetson AGX Thor headless quick start")
    print(String(repeating: "-", count: 72))
    print("User: \(resolvedUsername)")
    print("")

    if let debugTTY = snapshot.debugSerialCandidates.first(where: { $0.recommended })?.path {
        print("[debug-usb]  \(debugTTY)")
        print("  UEFI console:  \(JetsonThorQuickStartSupport.uefiConsoleCommand(serialPath: debugTTY))")
    } else {
        print("[debug-usb]  not detected")
        print("  fix: connect the Mac to Thor Debug-USB port 8 and re-run this command")
        print("  helper: Scripts/jetson-thor/thor_serial.sh list")
    }

    if let oemTTY = snapshot.oemConfigCandidates.first(where: { $0.recommended })?.path {
        print("[oem-config] \(oemTTY)")
        print("  Console:       \(JetsonThorQuickStartSupport.oemConfigConsoleCommand(serialPath: oemTTY))")
    } else {
        print("[oem-config] not detected yet")
        print("  note: this appears only after the installer finishes and the cable moves to USB-C 5a")
    }

    print("")
    if snapshot.usbTetherDetected {
        print("[usb-tether] host addresses: \(snapshot.usbTetherHostAddresses.joined(separator: ", "))")
    } else {
        print("[usb-tether] no 192.168.55.x host address detected yet")
        print("  fix: confirm the cable is in Thor USB-C 5a and wait for the tether interface to appear")
    }
    print("  SSH:           \(JetsonThorQuickStartSupport.usbSSHCommand(username: resolvedUsername))")
    print("  JetPack:       \(JetsonThorQuickStartSupport.jetPackInstallCommand(username: resolvedUsername))")
    print("  Docker smoke:  \(JetsonThorQuickStartSupport.dockerSmokeTestCommand(username: resolvedUsername))")

    if let publicKey = snapshot.publicKeyCandidates.first(where: { $0.recommended })?.path {
        print("")
        print("[pubkey]      \(publicKey)")
        if let helper = quickStartHelperScript(named: "bootstrap_ssh.sh") {
            print("  Bootstrap:    \(JetsonThorQuickStartSupport.bootstrapHelperCommand(scriptPath: helper, target: "\(resolvedUsername)@192.168.55.1", publicKeyPath: publicKey))")
        } else {
            print("  Bootstrap:    Scripts/jetson-thor/bootstrap_ssh.sh \(resolvedUsername)@192.168.55.1 \(publicKey)")
        }
    } else {
        print("")
        print("[pubkey]      no public key detected under ~/.ssh")
        print("  next: create one with \(JetsonThorQuickStartSupport.sshKeyGenerationCommand())")
    }

    print("")
    print("Summary:")
    print("  Debug-USB serials: \(snapshot.debugSerialCandidates.count)")
    print("  OEM-config serials: \(snapshot.oemConfigCandidates.count)")
    print("  USB tether: \(snapshot.usbTetherDetected ? "detected" : "not detected")")
    print("Docs:")
    print("  Repo runbook: docs/setup/jetson-agx-thor-headless-quickstart.md")
    print("  NVIDIA guide: https://docs.nvidia.com/jetson/agx-thor-devkit/user-guide/latest/quick_start.html")
}

private func quickStartHelperScript(named name: String) -> String? {
    let candidates = [
        ProcessInfo.processInfo.environment["THOR_JETSON_HELPERS_DIR"].map { "\($0)/\(name)" },
        FileManager.default.currentDirectoryPath + "/Scripts/jetson-thor/\(name)",
    ]

    return candidates
        .compactMap { $0 }
        .first(where: { FileManager.default.fileExists(atPath: $0) })
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

        print(tableRow([("ID", 4), ("NAME", 24), ("ENDPOINT", 32), ("STATUS", 8)]))
        print(String(repeating: "-", count: 78))
        for profile in profiles {
            print(tableRow([
                ("\(profile.id ?? 0)", 4),
                (profile.displayName, 24),
                (profile.endpointLabel, 32),
                (profile.lastValidationStatus.rawValue, 8),
            ]))
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
        print(tableRow([("NAME", 15), ("IMAGE", 30), ("STATE", 12), ("STATUS", 30)]))
        print(String(repeating: "-", count: 90))
        for c in response.containers {
            print(tableRow([
                (c.name, 15),
                (c.image, 30),
                (c.state, 12),
                (c.status, 30),
            ]))
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

func ros2GraphCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.ros2Graph()
        print("ROS2 Graph (\(response.graph.nodes.count) nodes, \(response.graph.edges.count) edges)")
        print(String(repeating: "-", count: 72))
        for node in response.graph.nodes {
            print("NODE  \(node.name) [\(node.kind)]")
        }
        for edge in response.graph.edges {
            print("EDGE  \(edge.from) -> \(edge.to) via \(edge.topic) [\(edge.messageType)]")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func ros2ParamsCmd(port: Int, node: String) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.ros2Parameters(node: node.isEmpty ? nil : node)
        if response.parameters.isEmpty {
            print(response.error ?? "No ROS2 parameters found.")
            return
        }
        print("ROS2 Parameters (\(response.parameters.count)):")
        for parameter in response.parameters {
            let readOnly = parameter.readOnly ? " ro" : ""
            print("  \(parameter.node) :: \(parameter.name)=\(parameter.value) [\(parameter.type)\(readOnly)]")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func ros2ActionsCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.ros2Actions()
        if response.actions.isEmpty {
            print(response.error ?? "No ROS2 actions found.")
            return
        }
        print("ROS2 Actions (\(response.actions.count)):")
        for action in response.actions {
            print("  \(action.name) [\(action.type)]")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func streamsCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let response = try await client.streamCatalog()
        if response.streams.isEmpty {
            print("No streams found.")
            return
        }
        print("Streams (\(response.streams.count)):")
        for stream in response.streams {
            let topicSuffix = stream.topic.map { " \($0)" } ?? ""
            print("  [\(stream.kind.rawValue)] \(stream.id) — \(stream.origin.rawValue)\(topicSuffix)")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func streamStatsCmd(port: Int, sourceID: String?) async {
    let client = AgentClient(port: port)
    do {
        if let sourceID, !sourceID.isEmpty {
            let response = try await client.streamHealth(sourceID: sourceID)
            print("Stream \(response.health.sourceID)")
            print("  Status:      \(response.health.status.rawValue)")
            print("  FPS:         \(response.health.fps.map { String(format: "%.1f", $0) } ?? "—")")
            print("  Resolution:  \(response.health.width.map(String.init) ?? "—")x\(response.health.height.map(String.init) ?? "—")")
            print("  Last Frame:  \(response.health.lastFrameAt ?? "—")")
            print("  Transport:   \(response.health.transportHealthy ? "healthy" : "degraded")")
            print("  Timestamps:  \(response.health.timestampsSane ? "sane" : "skewed")")
            print("  Rate Band:   \(response.health.expectedRate ? "expected" : "unexpected")")
            return
        }

        let catalog = try await client.streamCatalog()
        for stream in catalog.streams {
            let health = try await client.streamHealth(sourceID: stream.id)
            print("\(stream.id): \(health.health.status.rawValue) — fps \(health.health.fps.map { String(format: "%.1f", $0) } ?? "—")")
        }
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
        print(tableRow([("MOUNT", 20), ("SIZE", 8), ("USED", 8), ("AVAIL", 8), ("USE%", 8)]))
        for fs in d.filesystems {
            print(tableRow([
                (fs.mount, 20),
                (fs.size, 8),
                (fs.used, 8),
                (fs.available, 8),
                (fs.percent, 8),
            ]))
        }
    } catch { print("Error: \(error.localizedDescription)") }
}

func camerasCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let c = try await client.cameras()
        print("Cameras (\(c.count)):")
        for cam in c.cameras {
            let source = cam.source.map { " \($0)" } ?? ""
            let preview = cam.previewPath != nil ? " snapshot" : ""
            print("  [\(cam.type)\(source)] \(cam.name) — \(cam.device)\(preview)")
        }
    } catch { print("Error: \(error.localizedDescription)") }
}

func cameraSnapshotCmd(port: Int, cameraID: String, outputPath: String) async {
    guard !cameraID.isEmpty else {
        print("Usage: thorctl camera-snapshot <port> <camera-id|bridge:camera-id> [output.jpg]")
        return
    }

    let normalizedCameraID: String
    if cameraID.hasPrefix("bridge:") {
        normalizedCameraID = String(cameraID.dropFirst("bridge:".count))
    } else {
        normalizedCameraID = cameraID
    }

    let client = AgentClient(port: port)
    do {
        let data = try await client.cameraSnapshot(cameraID: normalizedCameraID)
        let destinationURL = URL(fileURLWithPath: outputPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        try data.write(to: destinationURL)
        print("Saved camera snapshot to \(destinationURL.path)")
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func gpuCmd(port: Int) async {
    let client = AgentClient(port: port)
    do {
        let g = try await client.gpuDetail()
        print("GPU:        \(g.gpuName)")
        print("Backend:    \(g.backend == "mlx" ? "MLX / Metal" : "Jetson CUDA")")
        if let runtimeLabel = g.runtimeLabel {
            print("Runtime:    \(runtimeLabel)")
        }
        if let metalAvailable = g.metalAvailable {
            print("Metal:      \(metalAvailable ? "Available" : "Unavailable")")
        }
        if let cudaVersion = g.cudaVersion {
            print("CUDA:       \(cudaVersion)")
        }
        if let tensorrtVersion = g.tensorrtVersion {
            print("TensorRT:   \(tensorrtVersion)")
        }
        print("Memory:     \(g.memoryUsedMb)/\(g.memoryTotalMb) MB")
        if g.backend != "mlx" {
            print("Temp:       \(Int(g.temperatureC))°C")
            print("Power:      \(String(format: "%.1f", g.powerDrawW)) W")
        }
        if let cachedModels = g.cachedModels {
            print("Cached:     \(cachedModels)")
        }
        if let loadedModels = g.loadedModels {
            print("Loaded:     \(loadedModels)")
        }
        let m = try await client.modelList()
        if m.count > 0 {
            print("Models (\(m.count)):")
            for model in m.models { print("  [\(model.format)] \(model.name)") }
        } else {
            print("Models:     none cached")
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
        print(tableRow([("IFACE", 12), ("STATE", 6), ("IP", 18), ("MAC", 17)]))
        for iface in n.interfaces {
            let ip = iface.addresses?.first { $0.family == "inet" }?.address ?? "—"
            print(tableRow([
                (iface.name, 12),
                (iface.state ?? "?", 6),
                (ip, 18),
                (iface.mac ?? "", 17),
            ]))
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

func recipeRunCmd(port: Int, identifier: String, overrides: [String]) async {
    guard !identifier.isEmpty else {
        print("Usage: thorctl recipe run <port> <recipe-id|name> [KEY=VALUE ...]")
        return
    }

    do {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath)
        let records = try await db.reader.read { dbConn in
            try DeployRecipeRecord.fetchAll(dbConn)
        }

        let decoder = JSONDecoder()
        let recipes = records.compactMap { record -> DeployRecipe? in
            guard let data = record.recipeJSON.data(using: .utf8),
                  var recipe = try? decoder.decode(DeployRecipe.self, from: data)
            else { return nil }
            recipe.id = record.id
            return recipe
        }

        guard let recipe = recipes.first(where: {
            if let id = $0.id, String(id) == identifier { return true }
            return $0.name.caseInsensitiveCompare(identifier) == .orderedSame
        }) else {
            print("Recipe not found: \(identifier)")
            return
        }

        let client = AgentClient(port: port)
        var variableMap: [String: String] = [:]
        for variable in recipe.variables {
            variableMap[variable.key] = variable.defaultValue ?? ""
        }
        for override in overrides {
            let parts = override.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            variableMap[parts[0]] = parts[1]
        }

        print("Running recipe: \(recipe.name)")
        print(String(repeating: "-", count: 72))

        for prerequisite in recipe.prerequisites {
            let command = substituteRecipeVariables(in: prerequisite.command, variables: variableMap)
            let result = try await client.exec(command: command, timeout: 20)
            let combined = [result.stdout, result.stderr].joined(separator: "\n")
            let matched = prerequisite.expectedSubstring.map { combined.contains($0) } ?? (result.exitCode == 0)
            print("[\(matched ? "PASS" : "FAIL")] prerequisite \(prerequisite.name)")
            if !matched || result.exitCode != 0 {
                print("Stopping: prerequisite failed")
                return
            }
        }

        var failed = false
        for step in recipe.steps {
            let command = substituteRecipeVariables(in: step.command, variables: variableMap)
            print("[STEP] \(step.name) — \(step.type.rawValue)")
            let success: Bool
            switch step.type {
            case .registryPreflight:
                let registry = command.split(separator: "/").first.map(String.init) ?? command
                let response = try await client.validateDeviceRegistry(registryAddress: registry, image: command)
                success = response.ready
                for stage in response.stages {
                    print("  \(stage.name): \(stage.status.rawValue) — \(stage.message)")
                }
            case .dockerPull:
                let actualCommand = command.hasPrefix("docker ") ? command : "docker pull \(command)"
                let result = try await client.exec(command: actualCommand, timeout: step.timeout)
                success = result.exitCode == 0
                if !result.stdout.isEmpty { print(result.stdout) }
                if !result.stderr.isEmpty { print(result.stderr) }
            default:
                let result = try await client.exec(command: command, timeout: step.timeout)
                success = result.exitCode == 0
                if !result.stdout.isEmpty { print(result.stdout) }
                if !result.stderr.isEmpty { print(result.stderr) }
            }

            if !success {
                failed = true
                print("[FAIL] \(step.name)")
                if step.stopOnFailure { break }
            } else {
                print("[PASS] \(step.name)")
            }
        }

        if !failed {
            for assertion in recipe.readinessAssertions {
                let command = substituteRecipeVariables(in: assertion.command, variables: variableMap)
                let result = try await client.exec(command: command, timeout: 20)
                let combined = [result.stdout, result.stderr].joined(separator: "\n")
                let matched = assertion.expectedSubstring.map { combined.contains($0) } ?? (result.exitCode == 0)
                print("[\(matched ? "PASS" : "FAIL")] assertion \(assertion.name)")
                if !matched {
                    failed = true
                }
            }
        }

        if failed, !recipe.rollbackSteps.isEmpty {
            print("")
            print("Rollback guidance:")
            for step in recipe.rollbackSteps {
                let command = substituteRecipeVariables(in: step.command, variables: variableMap)
                print("  - \(step.name): \(command)")
            }
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

func diagnosticsCollectCmd(port: Int, outputPath: String) async {
    let client = AgentClient(port: port)
    do {
        let data = try await client.diagnosticsArchive()
        let destinationURL = URL(fileURLWithPath: outputPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        try data.write(to: destinationURL)
        print("Saved diagnostics archive to \(destinationURL.path)")
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

private func substituteRecipeVariables(in template: String, variables: [String: String]) -> String {
    variables.reduce(template) { partialResult, entry in
        partialResult.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value)
    }
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
            let load = m.cpu.loadAvg.map { String(format: "%.2f", $0) }.joined(separator: " ")
            let line = "CPU: \(String(format: "%5.1f", m.cpu.percent))%  " +
                "MEM: \(String(format: "%4d", m.memory.usedMb))/\(String(format: "%4d", m.memory.totalMb)) MB " +
                "(\(String(format: "%4.0f", m.memory.percent))%)  " +
                "DISK: \(String(format: "%5.1f", m.disk.usedGb))/\(String(format: "%5.1f", m.disk.totalGb)) GB  " +
                "LOAD: \(load)"
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
      discover                      Probe registered devices and default simulator ports
      quickstart [username]         Print the Mac-side Jetson AGX Thor headless bring-up flow
      doctor [port]                 Run connection/readiness checks against a device
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
      cameras [port]                List detected and bridged cameras
      camera-snapshot <port> <camera-id|bridge:camera-id> [output.jpg]
                                   Save the latest camera snapshot from the agent

    ANIMA COMMANDS:
      anima-modules, modules [port]           List ANIMA modules
      anima-status [port]                     Show pipeline status
      anima-deploy <port> <compose.yaml>      Deploy ANIMA pipeline
      anima-stop <port> [pipeline-name]       Stop ANIMA pipeline

    ROS2 COMMANDS:
      ros2-nodes [port]             List ROS2 nodes
      ros2-topics [port]            List ROS2 topics
      ros2 graph [port]             Show ROS2 graph snapshot
      ros2 params [port] [node]     Show ROS2 parameters
      ros2 actions [port]           Show ROS2 actions

    STREAMS:
      streams [port]                List available image and scan streams
      stream-stats [port] [source]  Show stream health for one or all sources

    RECIPES / DIAGNOSTICS:
      recipe run <port> <recipe> [KEY=VALUE ...]
                                   Run a typed deploy recipe from the THOR database
      diagnostics collect <port> [output.zip]
                                   Save a diagnostics archive from the device

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
