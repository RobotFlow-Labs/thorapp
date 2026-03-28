import SwiftUI
import THORShared

struct DockerView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var containers: [DockerContainer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedContainer: DockerContainer?
    @State private var containerLogs: String = ""
    @State private var showingLogs = false
    @State private var containerToStop: String?
    @State private var containerToRemove: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
            }
            containerList
        }
        .task { await loadContainers() }
        .alert("Stop Container", isPresented: Binding(
            get: { containerToStop != nil },
            set: { if !$0 { containerToStop = nil } }
        )) {
            Button("Stop", role: .destructive) {
                if let name = containerToStop {
                    Task { await performAction(container: name, action: "stop") }
                }
                containerToStop = nil
            }
            Button("Cancel", role: .cancel) { containerToStop = nil }
        } message: {
            Text("Stop container \"\(containerToStop ?? "")\"?")
        }
    }

    private var headerRow: some View {
        HStack {
            Label("Docker Containers", systemImage: "shippingbox")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Button {
                Task { await loadContainers() }
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

    private var containerList: some View {
        VStack(spacing: 0) {
            if containers.isEmpty && !isLoading {
                Text("No containers found")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .padding(12)
            } else {
                ForEach(containers) { container in
                    containerRow(container)
                    if container.id != containers.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
        .sheet(isPresented: $showingLogs) {
            containerLogsSheet
        }
    }

    private func containerRow(_ container: DockerContainer) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(container.state == "running" ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 13, weight: .medium))
                Text(container.image)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(container.state)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(container.state == "running" ? .green : .secondary)

            // Actions
            HStack(spacing: 4) {
                if container.state == "running" {
                    actionIcon("stop.fill", color: .orange) {
                        containerToStop = container.name
                    }
                    actionIcon("arrow.clockwise", color: .blue) {
                        Task { await performAction(container: container.name, action: "restart") }
                    }
                } else {
                    actionIcon("play.fill", color: .green) {
                        Task { await performAction(container: container.name, action: "start") }
                    }
                }
                actionIcon("doc.text", color: .secondary) {
                    Task { await showLogs(for: container) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func actionIcon(_ systemName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .foregroundStyle(color)
        }
        .buttonStyle(.borderless)
    }

    private var containerLogsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Logs: \(selectedContainer?.name ?? "")")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button("Close") { showingLogs = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                Text(containerLogs)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 700, height: 500)
    }

    // MARK: - Actions

    private func loadContainers() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await client.dockerContainers()
            containers = response.containers
            if let err = response.error { errorMessage = err }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func performAction(container: String, action: String) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        do {
            _ = try await client.dockerAction(container: container, action: action)
            try? await Task.sleep(for: .seconds(1))
            await loadContainers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showLogs(for container: DockerContainer) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        selectedContainer = container
        do {
            let response = try await client.dockerLogs(container: container.name)
            containerLogs = response.logs
        } catch {
            containerLogs = "Failed to fetch logs: \(error.localizedDescription)"
        }
        showingLogs = true
    }
}
