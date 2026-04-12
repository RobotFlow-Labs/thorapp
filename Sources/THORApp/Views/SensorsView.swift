import AppKit
import SwiftUI
import THORShared

struct SensorsView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var streams: [StreamSource] = []
    @State private var selectedSourceID: String?
    @State private var imageData: Data?
    @State private var scanFrame: LaserScanFrame?
    @State private var health: StreamHealth?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pollingTask: Task<Void, Never>?

    private var selectedStream: StreamSource? {
        streams.first(where: { $0.id == selectedSourceID })
    }

    var body: some View {
        HStack(spacing: 20) {
            streamSidebar
                .frame(width: 240)

            VStack(alignment: .leading, spacing: 16) {
                header
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                if let selectedStream {
                    preview(for: selectedStream)
                    healthOverlay
                } else {
                    ContentUnavailableView(
                        "No Sensor Selected",
                        systemImage: "waveform.path.ecg",
                        description: Text("Pick an image or LaserScan source to start polling preview data.")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            await loadCatalog()
            startPolling()
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }

    private var streamSidebar: some View {
        GroupBox("Sources") {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(streams) { stream in
                        Button {
                            selectedSourceID = stream.id
                            Task { await refreshSelectedStream() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: stream.kind == .image ? "camera" : "waveform.path.ecg")
                                    .foregroundStyle(selectedSourceID == stream.id ? .white : .secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stream.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(stream.origin.rawValue.replacingOccurrences(of: "_", with: " "))
                                        .font(.system(size: 10))
                                        .foregroundStyle(selectedSourceID == stream.id ? .white.opacity(0.85) : .secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(selectedSourceID == stream.id ? Color.accentColor : Color(.secondarySystemFill).opacity(0.45))
                            .clipShape(.rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("Sensor Cockpit", systemImage: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .semibold))
                Text("Pull-based image preview and LaserScan inspection over the existing THOR tunnel.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await loadCatalog() }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func preview(for stream: StreamSource) -> some View {
        GroupBox(stream.name) {
            VStack(alignment: .leading, spacing: 12) {
                if stream.kind == .image {
                    if let imageData, let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 360)
                            .background(Color.black.opacity(0.92))
                            .clipShape(.rect(cornerRadius: 14))
                    } else {
                        placeholder("Waiting for JPEG preview…", systemImage: "photo")
                    }
                } else if let scanFrame {
                    LaserScanPlotView(scan: scanFrame)
                } else {
                    placeholder("Waiting for LaserScan frame…", systemImage: "dot.scope")
                }

                HStack(spacing: 12) {
                    Button("Capture Snapshot") {
                        captureSnapshot()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedStream == nil)

                    Button("Record 30s Bag") {
                        Task { await recordBag() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedStream == nil)
                }
            }
        }
    }

    private var healthOverlay: some View {
        GroupBox("Stream Health") {
            if let health {
                VStack(spacing: 0) {
                    metricRow("Status", value: health.status.rawValue.capitalized)
                    Divider()
                    metricRow("FPS", value: health.fps.map { String(format: "%.1f", $0) } ?? "—")
                    Divider()
                    metricRow("Resolution", value: resolutionLabel)
                    Divider()
                    metricRow("Last Frame", value: health.lastFrameAt ?? "—")
                    Divider()
                    metricRow("Transport", value: health.transportHealthy ? "Healthy" : "Degraded")
                    Divider()
                    metricRow("Timestamps", value: health.timestampsSane ? "Sane" : "Skewed")
                    Divider()
                    metricRow("Rate Band", value: health.expectedRate ? "Expected" : "Unexpected")
                }
            } else {
                Text("No health data yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    private var resolutionLabel: String {
        if let health, let width = health.width, let height = health.height {
            return "\(width)×\(height)"
        }
        if let selectedStream, let width = selectedStream.width, let height = selectedStream.height {
            return "\(width)×\(height)"
        }
        return "—"
    }

    private func placeholder(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: 280)
            .background(Color(.secondarySystemFill).opacity(0.45))
            .clipShape(.rect(cornerRadius: 14))
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func loadCatalog() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let catalog = try await client.streamCatalog()
            streams = catalog.streams
            if selectedSourceID == nil {
                selectedSourceID = streams.first?.id
            }
            await refreshSelectedStream()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await refreshSelectedStream()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshSelectedStream() async {
        guard let selectedStream,
              let client = appState.connector?.agentClient(for: deviceID)
        else { return }

        do {
            let healthResponse = try await client.streamHealth(sourceID: selectedStream.id)
            health = healthResponse.health

            switch selectedStream.kind {
            case .image:
                imageData = try await client.latestStreamImage(sourceID: selectedStream.id)
                scanFrame = nil
            case .scan:
                let scanResponse = try await client.latestLaserScan(sourceID: selectedStream.id)
                scanFrame = scanResponse.scan
                health = scanResponse.metadata ?? healthResponse.health
                imageData = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func captureSnapshot() {
        guard let selectedStream else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = selectedStream.kind == .image ? "\(selectedStream.id).jpg" : "\(selectedStream.id)-scan.json"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                switch selectedStream.kind {
                case .image:
                    guard let imageData else { return }
                    try imageData.write(to: url)
                case .scan:
                    guard let scanFrame else { return }
                    let data = try JSONEncoder().encode(scanFrame)
                    try data.write(to: url)
                }
                errorMessage = "Saved snapshot to \(url.path)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func recordBag() async {
        guard let selectedStream,
              let client = appState.connector?.agentClient(for: deviceID)
        else { return }

        let topic = selectedStream.topic ?? (selectedStream.kind == .image ? "/camera/image_raw" : "/scan")
        do {
            let response = try await client.ros2BagRecord(
                topics: [topic],
                output: "/tmp/thor_bag_\(selectedStream.id.replacingOccurrences(of: "/", with: "_"))"
            )
            errorMessage = "Recording bag for 30 seconds on \(topic)…"
            try? await Task.sleep(for: .seconds(30))
            if let pid = response.pid {
                _ = try await client.ros2BagStop(pid: pid)
            }
            errorMessage = "Bag recording completed for \(topic)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
