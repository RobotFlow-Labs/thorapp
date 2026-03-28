import Foundation
import THORShared
import AppKit

/// Exports a debug bundle containing logs, metrics, capabilities, and job history.
@MainActor
final class DebugBundleExporter {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Export a debug bundle for a device.
    func export(for device: Device) async throws {
        guard let deviceID = device.id else { return }

        var bundle: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "thorVersion": "0.1.0",
            "device": [
                "id": deviceID,
                "name": device.displayName,
                "hostname": device.hostname,
                "ip": device.lastKnownIP ?? "unknown",
                "environment": device.environment.rawValue,
                "tags": device.tags,
            ] as [String: Any],
        ]

        // Capabilities
        if let snapshot = try? await appState.latestSnapshot(for: deviceID) {
            bundle["capabilities"] = [
                "model": snapshot.jetsonModel,
                "os": snapshot.osRelease,
                "jetpack": snapshot.jetpackVersion ?? "N/A",
                "agent": snapshot.agentVersion,
                "docker": snapshot.dockerVersion ?? "N/A",
                "ros2": snapshot.ros2Presence,
                "support": snapshot.supportStatus.rawValue,
                "capturedAt": ISO8601DateFormatter().string(from: snapshot.capturedAt),
            ] as [String: Any]
        }

        // Connection state
        if let state = appState.connectionState(for: deviceID) {
            bundle["connection"] = [
                "status": state.status.rawValue,
                "lastChecked": ISO8601DateFormatter().string(from: state.lastCheckedAt),
                "failureReason": state.failureReason ?? "",
                "failureCode": state.failureCode ?? "",
            ]
        }

        // Live metrics
        if let metrics = try? await appState.fetchMetrics(for: deviceID) {
            bundle["metrics"] = [
                "cpu_percent": metrics.cpu.percent,
                "memory_used_mb": metrics.memory.usedMb,
                "memory_total_mb": metrics.memory.totalMb,
                "disk_used_gb": metrics.disk.usedGb,
                "disk_total_gb": metrics.disk.totalGb,
                "load_avg": metrics.cpu.loadAvg,
                "temperatures": metrics.temperatures,
            ] as [String: Any]
        }

        // Recent jobs
        if let db = appState.db {
            let jobs = try await db.reader.read { dbConn in
                try Job
                    .filter(Column("deviceID") == deviceID)
                    .order(Column("createdAt").desc)
                    .limit(20)
                    .fetchAll(dbConn)
            }
            bundle["recentJobs"] = jobs.map { job in
                [
                    "type": job.jobType.rawValue,
                    "status": job.status.rawValue,
                    "createdAt": ISO8601DateFormatter().string(from: job.createdAt),
                    "error": job.errorSummary ?? "",
                ] as [String: Any]
            }
        }

        // Agent logs
        if let client = appState.connector?.agentClient(for: deviceID) {
            let systemLogs = try? await client.systemLogs(lines: 50)
            let agentLogs = try? await client.agentLogs(lines: 50)
            bundle["logs"] = [
                "system": systemLogs?.lines ?? [],
                "agent": agentLogs?.lines ?? [],
            ]
        }

        // Serialize to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys])

        // Present save dialog
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "thor-debug-\(device.displayName)-\(dateString()).json"
        panel.allowedContentTypes = [.json]
        panel.title = "Export Debug Bundle"

        if panel.runModal() == .OK, let url = panel.url {
            try jsonData.write(to: url)
        }
    }

    private func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}
