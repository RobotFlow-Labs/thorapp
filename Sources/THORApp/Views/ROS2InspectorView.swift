import SwiftUI
import THORShared

struct ROS2InspectorView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var nodes: [String] = []
    @State private var topics: [ROS2Topic] = []
    @State private var services: [ROS2Service] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPanel = ROS2Panel.nodes

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.orange).font(.system(size: 12))
            }
            panelContent
        }
        .task { await loadAll() }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Label("ROS2 Inspector", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 14, weight: .medium))

            Picker("Panel", selection: $selectedPanel) {
                ForEach(ROS2Panel.allCases, id: \.self) { panel in
                    Text(panel.label).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            Button {
                Task { await loadAll() }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedPanel {
        case .nodes:
            nodesPanel
        case .topics:
            topicsPanel
        case .services:
            servicesPanel
        }
    }

    private var nodesPanel: some View {
        VStack(spacing: 0) {
            if nodes.isEmpty {
                emptyPanel("No ROS2 nodes detected")
            } else {
                ForEach(nodes, id: \.self) { node in
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.green)
                        Text(node)
                            .font(.system(size: 13, design: .monospaced))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    if node != nodes.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var topicsPanel: some View {
        VStack(spacing: 0) {
            if topics.isEmpty {
                emptyPanel("No ROS2 topics detected")
            } else {
                ForEach(topics) { topic in
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(topic.name)
                            .font(.system(size: 13, design: .monospaced))
                        Spacer()
                        Text(topic.type)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    if topic.id != topics.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var servicesPanel: some View {
        VStack(spacing: 0) {
            if services.isEmpty {
                emptyPanel("No ROS2 services detected")
            } else {
                ForEach(services) { service in
                    HStack {
                        Image(systemName: "bolt.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(service.name)
                            .font(.system(size: 13, design: .monospaced))
                        Spacer()
                        Text(service.type)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    if service.id != services.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func emptyPanel(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }

    private func loadAll() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let n = client.ros2Nodes()
            async let t = client.ros2Topics()
            async let s = client.ros2Services()
            let (nodesResp, topicsResp, servicesResp) = try await (n, t, s)
            nodes = nodesResp.nodes
            topics = topicsResp.topics
            services = servicesResp.services
            // Show error from any endpoint
            errorMessage = nodesResp.error ?? topicsResp.error ?? servicesResp.error
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private enum ROS2Panel: String, CaseIterable {
    case nodes, topics, services

    var label: String {
        rawValue.capitalized
    }
}
