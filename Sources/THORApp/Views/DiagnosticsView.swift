import AppKit
import SwiftUI
import THORShared

struct DiagnosticsView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var isCollecting = false
    @State private var statusMessage: String?
    @State private var latestArchiveURL: URL?
    @State private var recentBundles: [DiagnosticRunRecord] = []
    @State private var recentRecipeRuns: [RecipeRun] = []

    private var deviceID: Int64 { device.id ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ReadinessBoardView(deviceID: deviceID)
            bundleContents
            recentBundlesCard
            recentRecipeRunsCard
            recentEventsCard
        }
        .task(id: device.id) {
            await reload()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics Bundle", systemImage: "stethoscope")
                    .font(.system(size: 15, weight: .semibold))
                Text("Collect device evidence, readiness state, recent runs, and local app context into a shareable archive.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await collectBundle() }
            } label: {
                if isCollecting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Collect Bundle", systemImage: "archivebox")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCollecting)
        }
    }

    private var bundleContents: some View {
        GroupBox("Bundle Contents") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent health and capabilities")
                Text("Readiness board snapshot")
                Text("Thermal, power, and system metrics")
                Text("Docker inventory and ROS2 graph surfaces")
                Text("Sensor stream catalog and health")
                Text("Recent app events and deploy recipe history")
                Text("Selected logs plus a machine-readable manifest")
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recentBundlesCard: some View {
        GroupBox("Recent Bundles") {
            if recentBundles.isEmpty {
                emptyState("No diagnostics archives collected yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(recentBundles) { run in
                        let manifest = manifest(for: run)
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(manifest?.deviceName ?? device.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(run.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(URL(fileURLWithPath: run.archivePath).lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: run.archivePath)])
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 8)

                        if run.id != recentBundles.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var recentRecipeRunsCard: some View {
        GroupBox("Recent Recipe Runs") {
            if recentRecipeRuns.isEmpty {
                emptyState("Deploy recipe history will appear here after the first run.")
            } else {
                VStack(spacing: 0) {
                    ForEach(recentRecipeRuns) { run in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.recipeName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(run.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(color(for: run.status))
                        }
                        .padding(.vertical, 8)

                        if run.id != recentRecipeRuns.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var recentEventsCard: some View {
        GroupBox("Recent App Events") {
            let events = Array(appState.recentEvents.suffix(12)).reversed()
            if events.isEmpty {
                emptyState("App-level events will appear here as connections, recipes, and diagnostics run.")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func collectBundle() async {
        isCollecting = true
        defer { isCollecting = false }

        do {
            let archiveURL = try await appState.collectDiagnostics(for: device)
            latestArchiveURL = archiveURL
            statusMessage = "Collected diagnostics archive at \(archiveURL.path)."
            NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
            await reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func reload() async {
        do {
            async let bundles = appState.recentDiagnosticRuns(for: deviceID)
            async let recipes = appState.recentRecipeRuns(for: deviceID)
            recentBundles = try await bundles
            recentRecipeRuns = try await recipes
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func manifest(for record: DiagnosticRunRecord) -> DiagnosticBundleManifest? {
        guard let data = record.manifestJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DiagnosticBundleManifest.self, from: data)
    }

    private func color(for status: RecipeRunStatus) -> Color {
        switch status {
        case .created, .running:
            .orange
        case .success:
            .green
        case .failed:
            .red
        case .rolledBack:
            .secondary
        }
    }
}
