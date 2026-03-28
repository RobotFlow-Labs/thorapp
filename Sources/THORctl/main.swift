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
    case "connect":
        let host = args.count > 2 ? args[2] : "localhost"
        let port = args.count > 3 ? Int(args[3]) ?? 8470 : 8470
        await connectDevice(host: host, port: port)
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

// MARK: - Help

func printUsage() {
    print("""
    thorctl — THOR CLI for Jetson device management

    USAGE:
      thorctl <command> [port] [args...]

    DEVICE COMMANDS:
      devices, ls                   List registered devices
      connect <host> [port]         Connect and show device info
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
