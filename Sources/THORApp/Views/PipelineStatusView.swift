import SwiftUI
import THORShared

struct PipelineStatusView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var status: AnimaStatusResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.orange).font(.system(size: 12))
            }
            if let status {
                pipelineList(status)
            } else if isLoading {
                ProgressView("Loading pipeline status...")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                emptyState
            }
        }
        .task { await loadStatus() }
    }

    private var headerRow: some View {
        HStack {
            Label("Pipeline Status", systemImage: "play.rectangle.on.rectangle")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Button {
                Task { await loadStatus() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No pipelines deployed")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func pipelineList(_ response: AnimaStatusResponse) -> some View {
        VStack(spacing: 12) {
            ForEach(response.pipelines) { pipeline in
                pipelineCard(pipeline)
            }
        }
    }

    private func pipelineCard(_ pipeline: AnimaPipelineStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(pipeline.status == "running" ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(pipeline.name)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(pipeline.status.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(pipeline.status == "running" ? .green : .secondary)

                Button("Stop") {
                    Task { await stopPipeline(pipeline.name) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
            }

            if let containers = pipeline.containers, !containers.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(containers.enumerated()), id: \.offset) { _, container in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(container.State == "running" ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(container.Service ?? container.Name ?? "—")
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text(container.State ?? "—")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
                .background(Color(.secondarySystemFill).opacity(0.3))
                .clipShape(.rect(cornerRadius: 6))
            }

            if let error = pipeline.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func loadStatus() async {
        guard let deployer = appState.pipelineDeployer else { return }
        isLoading = true
        errorMessage = nil
        do {
            status = try await deployer.fetchStatus(for: device)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func stopPipeline(_ name: String) async {
        guard let deployer = appState.pipelineDeployer else { return }
        do {
            try await deployer.stop(pipelineName: name, on: device)
            try? await Task.sleep(for: .seconds(1))
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
