import SwiftUI
import THORShared
import UniformTypeIdentifiers

struct FileTransferView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var localPath = ""
    @State private var remotePath = "/home/jetson/"
    @State private var transferProgress: TransferProgress?
    @State private var isTransferring = false
    @State private var lastResult: TransferResult?
    @State private var transferMode = TransferMode.sync
    @State private var isDragTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            pathConfiguration
            dropZone
            if let progress = transferProgress {
                progressView(progress)
            }
            if let result = lastResult {
                resultView(result)
            }
            actionBar
        }
    }

    private var headerRow: some View {
        HStack {
            Label("File Transfer", systemImage: "arrow.up.doc")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Picker("Mode", selection: $transferMode) {
                Text("Sync").tag(TransferMode.sync)
                Text("Upload").tag(TransferMode.upload)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    private var pathConfiguration: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Local:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField("Path to sync", text: $localPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse") {
                    browseLocal()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            HStack {
                Text("Remote:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField("Target path on Jetson", text: $remotePath)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
                isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
            )
            .frame(height: 80)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 20))
                        .foregroundStyle(isDragTargeted ? .primary : .tertiary)
                    Text("Drop files or folders here")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers)
            }
    }

    private func progressView(_ progress: TransferProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.phase.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(progress.percent)%")
                    .font(.system(size: 12, design: .monospaced))
            }
            ProgressView(value: Double(progress.percent), total: 100)
                .tint(progress.phase == .failed ? .red : .accentColor)
            Text(progress.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func resultView(_ result: TransferResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.exitCode == 0 ? .green : .red)
            Text(result.exitCode == 0 ? "Transfer succeeded" : "Transfer failed (exit \(result.exitCode))")
                .font(.system(size: 12))
            Spacer()
        }
        .padding(8)
        .background((result.exitCode == 0 ? Color.green : Color.red).opacity(0.1))
        .clipShape(.rect(cornerRadius: 6))
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            Button {
                Task { await startTransfer() }
            } label: {
                if isTransferring {
                    ProgressView().controlSize(.small)
                } else {
                    Label(
                        transferMode == .sync ? "Sync" : "Upload",
                        systemImage: transferMode == .sync ? "arrow.triangle.2.circlepath" : "arrow.up"
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(localPath.isEmpty || isTransferring)
        }
    }

    // MARK: - Actions

    private func browseLocal() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = transferMode == .upload
        panel.canChooseDirectories = transferMode == .sync
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            localPath = url.path
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                Task { @MainActor in
                    localPath = url.path
                }
            }
        }
        return true
    }

    private func startTransfer() async {
        guard let deviceID = device.id else { return }
        isTransferring = true
        lastResult = nil

        let service = FileTransferService(appState: appState)

        // Resolve SSH target for Docker sim
        let host = device.hostname
        let port = (host == "localhost" || host == "127.0.0.1") ? 2222 : 22

        do {
            let result: TransferResult
            switch transferMode {
            case .sync:
                result = try await service.syncDirectory(
                    deviceID: deviceID,
                    localPath: localPath,
                    remotePath: remotePath,
                    port: port,
                    hostname: host
                ) { progress in
                    transferProgress = progress
                }
            case .upload:
                result = try await service.uploadFile(
                    deviceID: deviceID,
                    localPath: localPath,
                    remotePath: remotePath,
                    port: port,
                    hostname: host
                ) { progress in
                    transferProgress = progress
                }
            }
            lastResult = result
        } catch {
            transferProgress = TransferProgress(phase: .failed, percent: 0, message: error.localizedDescription)
        }

        isTransferring = false
    }
}

private enum TransferMode: String, CaseIterable {
    case sync
    case upload
}

extension TransferPhase {
    var label: String {
        switch self {
        case .starting: "Starting..."
        case .transferring: "Transferring"
        case .verifying: "Verifying"
        case .completed: "Complete"
        case .failed: "Failed"
        }
    }
}
