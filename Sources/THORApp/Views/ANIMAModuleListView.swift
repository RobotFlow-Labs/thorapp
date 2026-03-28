import SwiftUI
import THORShared

struct ANIMAModuleListView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var modules: [ANIMAModuleManifest] = []
    @State private var selectedModules: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingComposer = false
    @State private var filterText = ""
    @State private var devicePlatform: JetsonPlatform = .generic

    private var filteredModules: [ANIMAModuleManifest] {
        if filterText.isEmpty { return modules }
        return modules.filter {
            $0.displayName.localizedCaseInsensitiveContains(filterText) ||
            $0.category.localizedCaseInsensitiveContains(filterText) ||
            $0.capabilities.contains { $0.type.localizedCaseInsensitiveContains(filterText) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.orange).font(.system(size: 12))
            }
            moduleGrid
        }
        .task {
            // Load platform from device snapshot
            if let snap = try? await appState.latestSnapshot(for: device.id ?? 0) {
                devicePlatform = JetsonPlatform.from(model: snap.jetsonModel)
            }
            await loadModules()
        }
        .sheet(isPresented: $showingComposer) {
            let selected = modules.filter { selectedModules.contains($0.name) }
            PipelineComposerView(device: device, modules: selected)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Label("ANIMA Modules", systemImage: "brain")
                .font(.system(size: 14, weight: .medium))

            TextField("Filter...", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            Spacer()

            if !selectedModules.isEmpty {
                Button("Compose Pipeline (\(selectedModules.count))") {
                    showingComposer = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button {
                Task { await loadModules() }
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

    private var moduleGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 12)], spacing: 12) {
            ForEach(filteredModules) { module in
                moduleCard(module)
            }
        }
    }

    private func moduleCard(_ module: ANIMAModuleManifest) -> some View {
        let isSelected = selectedModules.contains(module.name)
        let isCompatible = module.supportsJetson(devicePlatform)

        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Text("v\(module.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCompatible {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            // Category
            Text(module.category)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            // Capabilities
            HStack(spacing: 4) {
                ForEach(module.capabilities, id: \.type) { cap in
                    Text(cap.type)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 4))
                }
            }

            // IO summary
            HStack(spacing: 12) {
                Label("\(module.inputs.count) in", systemImage: "arrow.down.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Label("\(module.outputs.count) out", systemImage: "arrow.up.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Performance
            if let perf = module.performanceProfiles.first {
                HStack(spacing: 8) {
                    if let fps = perf.fps {
                        Text("\(Int(fps)) FPS")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    if let latency = perf.latencyP50Ms {
                        Text("\(Int(latency))ms p50")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    if let mem = perf.memoryMb {
                        Text("\(mem) MB")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    Text(perf.backend)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            // Container
            Text(module.containerImage)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .onTapGesture {
            if isSelected {
                selectedModules.remove(module.name)
            } else if isCompatible {
                selectedModules.insert(module.name)
            }
        }
        .opacity(isCompatible ? 1.0 : 0.5)
    }

    private func loadModules() async {
        guard let deployer = appState.pipelineDeployer else { return }
        isLoading = true
        errorMessage = nil
        do {
            modules = try await deployer.fetchModules(for: device)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
