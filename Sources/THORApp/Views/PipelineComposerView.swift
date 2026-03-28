import SwiftUI
import THORShared

struct PipelineComposerView: View {
    let device: Device
    let modules: [ANIMAModuleManifest]
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var pipelineName = ""
    @State private var composedYAML = ""
    @State private var validationIssues: [PipelineValidationIssue] = []
    @State private var isDeploying = false
    @State private var deployResult: String?
    @State private var deploySuccess = false

    private let composer = PipelineComposer()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Compose Pipeline")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    configSection
                    moduleSummary
                    if !validationIssues.isEmpty {
                        validationSection
                    }
                    yamlPreview
                    if let deployResult {
                        resultSection(deployResult)
                    }
                }
                .padding(20)
            }

            Divider()
            actionBar
        }
        .frame(width: 700, height: 600)
        .onAppear { generateCompose() }
    }

    private var configSection: some View {
        GroupBox("Pipeline Configuration") {
            HStack {
                Text("Name:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("my-pipeline", text: $pipelineName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pipelineName) { generateCompose() }
            }
            .padding(8)
        }
    }

    private var moduleSummary: some View {
        GroupBox("Selected Modules (\(modules.count))") {
            VStack(spacing: 0) {
                ForEach(modules) { module in
                    HStack {
                        Text(module.displayName)
                            .font(.system(size: 13, weight: .medium))
                        Text("v\(module.version)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(module.preferredBackend(for: .thor))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                        if let perf = module.performanceProfiles.first {
                            if let mem = perf.memoryMb {
                                Text("\(mem) MB")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    if module.name != modules.last?.name {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }

    private var validationSection: some View {
        GroupBox("Validation") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(validationIssues) { issue in
                    HStack(spacing: 6) {
                        Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .font(.system(size: 11))
                        Text(issue.message)
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(8)
        }
    }

    private var yamlPreview: some View {
        GroupBox("Generated docker-compose.yaml") {
            ScrollView {
                Text(composedYAML)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color(.textBackgroundColor))
            .clipShape(.rect(cornerRadius: 6))
        }
    }

    private func resultSection(_ result: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: deploySuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(deploySuccess ? .green : .red)
            Text(result)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(8)
        .background((deploySuccess ? Color.green : Color.red).opacity(0.1))
        .clipShape(.rect(cornerRadius: 6))
    }

    private var actionBar: some View {
        HStack {
            Button("Copy YAML") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(composedYAML, forType: .string)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                Task { await deploy() }
            } label: {
                if isDeploying {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Deploy to \(device.displayName)", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                isDeploying ||
                pipelineName.isEmpty ||
                validationIssues.contains { $0.severity == .error }
            )
        }
        .padding(16)
    }

    private func generateCompose() {
        let platform = JetsonPlatform.from(model: "Jetson Thor")
        composedYAML = composer.compose(modules: modules, platform: platform)
        validationIssues = composer.validateCompatibility(modules: modules, platform: platform)
    }

    private func deploy() async {
        guard let deployer = appState.pipelineDeployer else { return }
        isDeploying = true
        deployResult = nil
        do {
            let pipeline = try await deployer.deploy(
                modules: modules,
                to: device,
                pipelineName: pipelineName.isEmpty ? "default" : pipelineName
            )
            deploySuccess = true
            deployResult = "Pipeline '\(pipeline.name)' deployed successfully"
        } catch {
            deploySuccess = false
            deployResult = error.localizedDescription
        }
        isDeploying = false
    }
}
