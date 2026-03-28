import Foundation
import THORShared

/// Orchestrates ANIMA pipeline deployment: compose → deploy → monitor.
@MainActor
final class PipelineDeployer {
    private let appState: AppState
    private let composer = PipelineComposer()

    init(appState: AppState) {
        self.appState = appState
    }

    /// Deploy a pipeline of selected modules to a device.
    func deploy(
        modules: [ANIMAModuleManifest],
        to device: Device,
        pipelineName: String
    ) async throws -> Pipeline {
        guard let deviceID = device.id,
              let client = appState.connector?.agentClient(for: deviceID) else {
            throw PipelineDeployerError.deviceNotConnected
        }

        // Determine platform
        let snapshot = try? await appState.latestSnapshot(for: deviceID)
        let platform = JetsonPlatform.from(model: snapshot?.jetsonModel ?? "Jetson")

        // Validate compatibility
        let gpuMem = snapshot?.capabilitiesJSON.flatMap { _ in 0 } ?? 0  // TODO: parse from capabilities
        let issues = composer.validateCompatibility(modules: modules, platform: platform, gpuMemoryMB: gpuMem)
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            throw PipelineDeployerError.incompatible(errors.map(\.message).joined(separator: "; "))
        }

        // Compose docker-compose YAML
        let yaml = composer.compose(modules: modules, platform: platform)

        // Create pipeline record
        let pipeline = Pipeline(
            name: pipelineName,
            description: "Modules: \(modules.map(\.displayName).joined(separator: ", "))",
            modules: modules,
            deviceID: deviceID,
            status: .deploying,
            composeYAML: yaml
        )

        var pipelineID: Int64 = 0
        if let db = appState.db {
            pipelineID = try await db.writer.write { [pipeline] dbConn -> Int64 in
                var record = pipeline
                try record.insert(dbConn)
                return record.id ?? 0
            }
        }

        // Deploy via agent
        let response = try await client.animaDeploy(composeYAML: yaml, pipelineName: pipelineName)

        // Create run record
        let runStatus: PipelineStatus = response.status == "deployed" ? .running : .failed

        if let db = appState.db {
            let run = PipelineRun(
                pipelineID: pipelineID,
                deviceID: deviceID,
                status: runStatus,
                errorSummary: response.status == "deployed" ? nil : response.stderr,
                logSnippet: response.stdout
            )
            try await db.writer.write { [run] dbConn in
                var record = run
                try record.insert(dbConn)
            }
        }

        if response.status != "deployed" {
            throw PipelineDeployerError.deployFailed(response.stderr ?? "Unknown error")
        }

        var result = pipeline
        result.status = runStatus
        return result
    }

    /// Stop a running pipeline on a device.
    func stop(pipelineName: String, on device: Device) async throws {
        guard let deviceID = device.id,
              let client = appState.connector?.agentClient(for: deviceID) else {
            throw PipelineDeployerError.deviceNotConnected
        }

        let response = try await client.animaStop(pipelineName: pipelineName)
        if response.status != "stopped" {
            throw PipelineDeployerError.stopFailed(response.stderr ?? "Unknown error")
        }
    }

    /// Fetch pipeline status from a device.
    func fetchStatus(for device: Device) async throws -> AnimaStatusResponse? {
        guard let deviceID = device.id,
              let client = appState.connector?.agentClient(for: deviceID) else {
            return nil
        }
        return try await client.animaStatus()
    }

    /// Fetch available ANIMA modules from a device.
    func fetchModules(for device: Device) async throws -> [ANIMAModuleManifest] {
        guard let deviceID = device.id,
              let client = appState.connector?.agentClient(for: deviceID) else {
            return []
        }
        let response = try await client.animaModules()
        return response.modules
    }
}

enum PipelineDeployerError: Error, LocalizedError {
    case deviceNotConnected
    case incompatible(String)
    case deployFailed(String)
    case stopFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotConnected: "Device is not connected"
        case .incompatible(let reason): "Incompatible: \(reason)"
        case .deployFailed(let err): "Deploy failed: \(err)"
        case .stopFailed(let err): "Stop failed: \(err)"
        }
    }
}
