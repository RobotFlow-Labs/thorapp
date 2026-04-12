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
        case .gpu: "gpu"
        case .logs: "doc.text"
        case .history: "clock.arrow.circlepath"
        case .diagnostics: "stethoscope"
        }
    }
}
