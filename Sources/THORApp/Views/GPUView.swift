import SwiftUI
import THORShared

struct GPUView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState
    @State private var gpuInfo: GPUDetailResponse?
    @State private var engines: TensorRTEnginesResponse?
    @State private var models: ModelListResponse?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("GPU & Models", systemImage: "gpu")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button { Task { await loadAll() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }

            if isLoading && gpuInfo == nil {
                ProgressView("Loading GPU info...").frame(maxWidth: .infinity, minHeight: 100)
            } else {
                gpuInfoCard
                memoryCard
                trtEnginesCard
                modelsCard
            }
        }
        .task { await loadAll() }
    }

    private var gpuInfoCard: some View {
        GroupBox("GPU") {
            if let g = gpuInfo {
                VStack(spacing: 0) {
                    infoRow("GPU", g.gpuName)
                    Divider().padding(.leading, 16)
                    infoRow("Backend", backendDisplayName(for: g))
                    if g.backend == "mlx" {
                        Divider().padding(.leading, 16)
                        infoRow("Metal", g.metalAvailable == true ? "Available" : "Unavailable")
                        Divider().padding(.leading, 16)
                        infoRow("Runtime", g.mlxBackend ?? g.runtimeLabel ?? "MLX")
                        Divider().padding(.leading, 16)
                        infoRow("Cached Models", "\(g.cachedModels ?? 0)")
                        Divider().padding(.leading, 16)
                        infoRow("Loaded Models", "\(g.loadedModels ?? 0)")
                    } else {
                        Divider().padding(.leading, 16)
                        infoRow("CUDA", g.cudaVersion ?? "N/A")
                        Divider().padding(.leading, 16)
                        infoRow("TensorRT", g.tensorrtVersion ?? "N/A")
                        Divider().padding(.leading, 16)
                        infoRow("Temperature", "\(Int(g.temperatureC))°C")
                        Divider().padding(.leading, 16)
                        infoRow("Power", "\(String(format: "%.1f", g.powerDrawW)) W")
                        Divider().padding(.leading, 16)
                        infoRow("Utilization", "\(Int(g.utilizationPercent))%")
                    }
                }
            }
        }
    }

    private var memoryCard: some View {
        GroupBox("GPU Memory") {
            if let g = gpuInfo, g.memoryTotalMb > 0 {
                VStack(spacing: 8) {
                    HStack {
                        Text("\(g.memoryUsedMb) MB used")
                            .font(.system(size: 13, design: .monospaced))
                        Spacer()
                        Text("\(g.memoryTotalMb) MB total")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(g.memoryUsedMb), total: Double(g.memoryTotalMb))
                        .tint(Double(g.memoryUsedMb) / Double(g.memoryTotalMb) > 0.9 ? .red : .blue)
                    Text("\(g.memoryTotalMb - g.memoryUsedMb) MB free")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(8)
            } else {
                Text("GPU memory info not available").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private var trtEnginesCard: some View {
        GroupBox("TensorRT Engines (\(engines?.count ?? 0))") {
            if gpuInfo?.backend == "mlx" {
                Text("TensorRT is not used when THOR is connected to docker_mlx_cpp on the host Mac.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .padding(8)
            } else if let eng = engines, !eng.engines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(eng.engines) { engine in
                        HStack {
                            Image(systemName: "gearshape.fill").foregroundStyle(.orange).font(.system(size: 10))
                            Text(engine.name).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(formatBytes(engine.sizeBytes))
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                }
            } else {
                Text("No TensorRT engines found").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private var modelsCard: some View {
        GroupBox("Models (\(models?.count ?? 0))") {
            if let m = models, !m.models.isEmpty {
                VStack(spacing: 0) {
                    ForEach(m.models) { model in
                        HStack {
                            formatBadge(model.format)
                            Text(model.name).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(formatBytes(model.sizeBytes))
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                }
            } else {
                Text("No models found").foregroundStyle(.secondary).font(.system(size: 13)).padding(8)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).font(.system(size: 13, design: .monospaced))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func formatBadge(_ format: String) -> some View {
        Text(format.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(formatColor(for: format))
            .clipShape(.rect(cornerRadius: 3))
    }

    private func backendDisplayName(for info: GPUDetailResponse) -> String {
        if info.backend == "mlx" {
            return "MLX / Metal"
        }
        return "Jetson CUDA"
    }

    private func formatColor(for format: String) -> Color {
        switch format.lowercased() {
        case "trt":
            return Color.orange.opacity(0.2)
        case "onnx":
            return Color.blue.opacity(0.2)
        case "mlx":
            return Color.teal.opacity(0.2)
        default:
            return Color.green.opacity(0.2)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func loadAll() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isLoading = true
        do {
            async let g = client.gpuDetail()
            async let e = client.tensorrtEngines()
            async let m = client.modelList()
            (gpuInfo, engines, models) = try await (g, e, m)
        } catch {}
        isLoading = false
    }
}
