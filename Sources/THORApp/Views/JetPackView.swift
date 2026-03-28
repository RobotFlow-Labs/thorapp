import SwiftUI
import THORShared

struct JetPackView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var snapshot: CompatibilitySnapshot?
    @State private var jetpackInfo: JetPackInfo?
    @State private var moduleCompatibility: [String: CompatibilityResult] = [:]
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            if isLoading {
                ProgressView("Loading JetPack information...")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if let snap = snapshot {
                jetpackDetailCard(snap)
                softwareStackCard(snap)
                compatibilityMatrixCard
            } else {
                noDataView
            }
        }
        .task { await loadData() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Label("JetPack Management", systemImage: "cpu.fill")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - JetPack Detail

    private func jetpackDetailCard(_ snap: CompatibilitySnapshot) -> some View {
        GroupBox("JetPack Version") {
            VStack(spacing: 0) {
                infoRow("JetPack", value: snap.jetpackVersion ?? "Unknown", highlight: true)
                Divider().padding(.leading, 16)
                infoRow("Jetson Model", value: snap.jetsonModel)
                Divider().padding(.leading, 16)
                infoRow("OS", value: snap.osRelease)

                if let info = jetpackInfo {
                    Divider().padding(.leading, 16)
                    infoRow("CUDA", value: info.cudaVersion ?? "Unknown")
                    Divider().padding(.leading, 16)
                    infoRow("TensorRT", value: info.tensorrtVersion ?? "Unknown")
                    Divider().padding(.leading, 16)
                    infoRow("L4T", value: info.l4tVersion ?? "Unknown")
                }
            }
        }
    }

    // MARK: - Software Stack

    private func softwareStackCard(_ snap: CompatibilitySnapshot) -> some View {
        GroupBox("Software Stack") {
            VStack(spacing: 0) {
                stackRow("Agent", version: snap.agentVersion, status: .installed)
                Divider().padding(.leading, 16)
                stackRow("Docker", version: snap.dockerVersion, status: snap.dockerVersion != nil ? .installed : .notInstalled)
                Divider().padding(.leading, 16)
                stackRow("ROS2", version: snap.ros2Presence ? "Detected" : nil, status: snap.ros2Presence ? .installed : .notInstalled)
                Divider().padding(.leading, 16)
                stackRow("Support", version: snap.supportStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                         status: snap.supportStatus == .supported ? .installed : .warning)
            }
        }
    }

    // MARK: - Compatibility Matrix

    private var compatibilityMatrixCard: some View {
        GroupBox("ANIMA Module Compatibility") {
            if moduleCompatibility.isEmpty {
                Text("Connect and load ANIMA modules to check compatibility")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(moduleCompatibility.keys.sorted()), id: \.self) { moduleName in
                        let result = moduleCompatibility[moduleName]!
                        HStack {
                            Image(systemName: result.isCompatible ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.isCompatible ? .green : .red)
                                .font(.system(size: 12))
                            Text(moduleName)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            switch result {
                            case .compatible(let backend, let notes):
                                HStack(spacing: 6) {
                                    Text(backend.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.orange)
                                    Text(notes)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            case .incompatible(let reason):
                                Text(reason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            case .unknown:
                                Text("Unknown")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)

                        if moduleName != moduleCompatibility.keys.sorted().last {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - No Data

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No JetPack information available")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Connect to the device to fetch JetPack details.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: highlight ? 15 : 13, weight: highlight ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(highlight ? .primary : .primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func stackRow(_ name: String, version: String?, status: StackStatus) -> some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 13))
                .frame(width: 80, alignment: .leading)
            Text(version ?? "Not installed")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(version != nil ? .primary : .secondary)
            Spacer()
            Text(status.label)
                .font(.system(size: 11))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func loadData() async {
        isLoading = true
        guard let deviceID = device.id else { isLoading = false; return }

        // Load snapshot
        snapshot = try? await appState.latestSnapshot(for: deviceID)

        // Compute JetPack info
        if let snap = snapshot {
            jetpackInfo = JetPackCompatibility.jetpackInfo(snap.jetpackVersion)
        }

        // Check ANIMA module compatibility
        if let client = appState.connector?.agentClient(for: deviceID) {
            if let modulesResp = try? await client.animaModules() {
                for module in modulesResp.modules {
                    let result = JetPackCompatibility.check(
                        module: module,
                        jetpackVersion: snapshot?.jetpackVersion,
                        gpuMemoryMB: 0
                    )
                    moduleCompatibility[module.displayName] = result
                }
            }
        }

        isLoading = false
    }
}

private enum StackStatus {
    case installed, notInstalled, warning

    var color: Color {
        switch self {
        case .installed: .green
        case .notInstalled: .gray
        case .warning: .orange
        }
    }

    var label: String {
        switch self {
        case .installed: "Installed"
        case .notInstalled: "Missing"
        case .warning: "Check"
        }
    }
}
