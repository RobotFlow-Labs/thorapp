import Foundation

enum WorkspaceSelection: String, Sendable {
    case devices
    case studio
    case fleet
    case registries
}

enum DetailTab: String, CaseIterable, Sendable {
    case overview
    case setup
    case system
    case power
    case hardware
    case sensors
    case docker
    case ros2
    case anima
    case files
    case deploy
    case gpu
    case logs
    case history
    case diagnostics

    var label: String {
        switch self {
        case .overview: "Overview"
        case .setup: "Setup"
        case .system: "System"
        case .power: "Power"
        case .hardware: "Hardware"
        case .sensors: "Sensors"
        case .docker: "Docker"
        case .ros2: "ROS2"
        case .anima: "ANIMA"
        case .files: "Files"
        case .deploy: "Deploy"
        case .gpu: "GPU & Models"
        case .logs: "Logs"
        case .history: "History"
        case .diagnostics: "Diagnostics"
        }
    }

    var icon: String {
        switch self {
        case .overview: "cpu"
        case .setup: "wrench.and.screwdriver"
        case .system: "info.circle"
        case .power: "bolt.fill"
        case .hardware: "cable.connector"
        case .sensors: "waveform.path.ecg"
        case .docker: "shippingbox"
        case .ros2: "point.3.connected.trianglepath.dotted"
        case .anima: "brain"
        case .files: "arrow.up.doc"
        case .deploy: "play.rectangle"
        case .gpu: "memorychip"
        case .logs: "doc.text"
        case .history: "clock.arrow.circlepath"
        case .diagnostics: "stethoscope"
        }
    }

    var help: DetailTabHelp {
        switch self {
        case .overview:
            DetailTabHelp(
                title: "Overview",
                summary: "Use Overview to confirm that the device is reachable, the agent is healthy, and the major runtime systems are ready before you drill into a specific tool.",
                startHere: [
                    "Check the connection card and readiness board first.",
                    "Use the quick actions to refresh, reconnect, or collect diagnostics.",
                ],
                lookFor: [
                    "Warnings about ROS2, sensors, storage, or registry readiness.",
                    "Capability rows that show whether JetPack, the agent, and support status were detected.",
                ]
            )
        case .setup:
            DetailTabHelp(
                title: "Setup",
                summary: "Setup is the recovery and first-boot page. It explains what is blocking a healthy session and links you to the next action instead of forcing guesswork.",
                startHere: [
                    "Read the doctor checklist from top to bottom.",
                    "Use Retry Connection when the device should already be reachable.",
                    "Use Install Agent after SSH access is working but THOR services are missing.",
                ],
                lookFor: [
                    "Blocked items for connection, agent install, or ROS2 readiness.",
                    "Suggested flows when you are bringing up a simulator or a new real Jetson.",
                ]
            )
        case .system:
            DetailTabHelp(
                title: "System",
                summary: "System shows the identity and health basics for the target: OS, kernel, uptime, disks, swap, network interfaces, and users.",
                startHere: [
                    "Verify the model, OS release, and JetPack/L4T version.",
                    "Check storage usage before large model or bag operations.",
                ],
                lookFor: [
                    "Unexpected root filesystem pressure or missing swap.",
                    "Network addresses that do not match the path you expected to use.",
                ]
            )
        case .power:
            DetailTabHelp(
                title: "Power",
                summary: "Power controls the device power mode, clocks, and fan behavior so you can move between quiet development settings and maximum performance modes.",
                startHere: [
                    "Confirm the current nvpmodel and clocks state before making changes.",
                    "Use the fan control when you need more thermal headroom during heavy workloads.",
                ],
                lookFor: [
                    "Thermal or performance mismatches between your expected mode and the current device state.",
                ]
            )
        case .hardware:
            DetailTabHelp(
                title: "Hardware",
                summary: "Hardware inventories cameras, GPIO, I2C, USB, and serial devices so you can confirm that attached peripherals are actually visible to the Jetson.",
                startHere: [
                    "Check the camera list before opening Sensors.",
                    "Use the bus and port inventories to confirm accessories are attached where you expect.",
                ],
                lookFor: [
                    "Missing peripherals, unexpected serial adapters, or camera bridge state that does not match the bench setup.",
                ]
            )
        case .sensors:
            DetailTabHelp(
                title: "Sensors",
                summary: "Sensors is the live cockpit for image and LaserScan streams. It helps you confirm that sensor topics are alive, on-rate, and worth recording.",
                startHere: [
                    "Select a source from the left-hand list.",
                    "Refresh the preview and inspect the stream health metrics.",
                    "Capture a snapshot or record a short bag once the stream looks sane.",
                ],
                lookFor: [
                    "Stale timestamps, missing frames, wrong resolution, or unhealthy transport state.",
                ]
            )
        case .docker:
            DetailTabHelp(
                title: "Docker",
                summary: "Docker lists running containers and exposes quick container actions. This is mainly useful for simulator and container-runtime workflows.",
                startHere: [
                    "Scan the container list for status, image, and uptime.",
                    "Open logs on a container that looks unhealthy before restarting it.",
                ],
                lookFor: [
                    "Exited or restarting containers that explain missing ANIMA or ROS2 behavior.",
                ]
            )
        case .ros2:
            DetailTabHelp(
                title: "ROS2",
                summary: "ROS2 Workbench gives you the graph, topics, services, parameters, launches, bags, and actions in one place so you can inspect a robotics runtime without using the shell.",
                startHere: [
                    "Start with Graph to confirm the expected nodes and edges exist.",
                    "Use Topics and Services when you need interface-level detail.",
                    "Open Parameters, Launches, or Bags when you are validating runtime behavior.",
                ],
                lookFor: [
                    "Missing nodes, dead topics, or parameter values that do not match the intended deployment.",
                ]
            )
        case .anima:
            DetailTabHelp(
                title: "ANIMA",
                summary: "ANIMA is where you inspect module availability and current pipeline state for higher-level robotics application workflows.",
                startHere: [
                    "Confirm the required modules are present.",
                    "Use the pipeline status view to see what is deployed and whether it is healthy.",
                ],
                lookFor: [
                    "Missing modules, unhealthy pipeline state, or runtime prerequisites that are still degraded.",
                ]
            )
        case .files:
            DetailTabHelp(
                title: "Files",
                summary: "Files handles quick operator transfers to and from the Jetson without opening a terminal session or remembering paths.",
                startHere: [
                    "Set the local path or drop files into the transfer target.",
                    "Verify the remote destination before syncing or uploading.",
                ],
                lookFor: [
                    "Wrong destination paths or unexpected usernames when working with real devices.",
                ]
            )
        case .deploy:
            DetailTabHelp(
                title: "Deploy",
                summary: "Deploy runs structured rollout recipes and registry-aware release actions so you can move from a validated runtime to a reproducible deployment.",
                startHere: [
                    "Check registry readiness before starting a deployment.",
                    "Use the recipe or deploy controls that match the target environment.",
                ],
                lookFor: [
                    "Registry trust problems, missing credentials, or runtime prerequisites that still block deployment.",
                ]
            )
        case .gpu:
            DetailTabHelp(
                title: "GPU & Models",
                summary: "GPU & Models shows GPU telemetry and model/runtime information so you can verify acceleration support before heavy inference work.",
                startHere: [
                    "Confirm the detected GPU and runtime support first.",
                    "Check model or TensorRT information before pushing new inference assets.",
                ],
                lookFor: [
                    "Missing GPU telemetry, unsupported runtimes, or model inventory mismatches.",
                ]
            )
        case .logs:
            DetailTabHelp(
                title: "Logs",
                summary: "Logs is the fastest way to inspect recent system or agent output from the device when something fails and you need proof, not guesses.",
                startHere: [
                    "Switch between System and Agent sources depending on the failure you are chasing.",
                    "Use the filter field to narrow down noisy output.",
                ],
                lookFor: [
                    "Startup failures, permission errors, missing services, or repeated reconnect messages.",
                ]
            )
        case .history:
            DetailTabHelp(
                title: "History",
                summary: "History keeps the local record of recent device events and transfers so you can reconstruct what happened during a session.",
                startHere: [
                    "Review the event timeline after debugging or deployment work.",
                    "Use transfer history to confirm which assets were moved and when.",
                ],
                lookFor: [
                    "Repeated failures, transfer retries, or session events that explain the current state of the device.",
                ]
            )
        case .diagnostics:
            DetailTabHelp(
                title: "Diagnostics",
                summary: "Diagnostics packages the current device state into a support archive so you can preserve evidence before changing anything else.",
                startHere: [
                    "Run a collection when the device is misbehaving but still reachable.",
                    "Save the archive before rebooting, redeploying, or replacing runtime components.",
                ],
                lookFor: [
                    "Readiness issues, ROS2 graph context, and runtime state that should travel with a support bundle.",
                ]
            )
        }
    }
}

struct DetailTabHelp: Sendable {
    let title: String
    let summary: String
    let startHere: [String]
    let lookFor: [String]
}
