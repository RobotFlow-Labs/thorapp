import Foundation
import GRDB
import THORShared

@MainActor
extension AppState {
    var guidedFlows: [GuidedFlow] {
        [
            GuidedFlow(
                id: "first-simulator-session",
                title: "First Simulator Session",
                summary: "Bring up the Docker sims, connect to Thor, and verify the readiness board.",
                steps: [
                    GuidedFlowStep(title: "Verify Docker", detail: "Confirm Docker Desktop is installed and running."),
                    GuidedFlowStep(title: "Start Sims", detail: "Launch the THOR Thor and Orin simulator containers."),
                    GuidedFlowStep(title: "Connect", detail: "Enroll localhost simulator devices and connect them directly."),
                    GuidedFlowStep(title: "Inspect", detail: "Open Overview and confirm readiness for connection, Docker, ROS2, and sensors."),
                ]
            ),
            GuidedFlow(
                id: "first-real-jetson",
                title: "First Real Jetson",
                summary: "Discover a real device, trust its host key, install the agent, and validate compatibility.",
                steps: [
                    GuidedFlowStep(title: "Discover", detail: "Scan the local network for Jetson devices."),
                    GuidedFlowStep(title: "Trust Host Key", detail: "Verify the first-seen SSH host key before saving the device."),
                    GuidedFlowStep(title: "Install Agent", detail: "Connect over SSH and push the THOR agent if needed."),
                    GuidedFlowStep(title: "Validate", detail: "Check JetPack, Docker, ROS2, storage, and runtime readiness."),
                ]
            ),
            GuidedFlow(
                id: "record-first-bag",
                title: "Record First Bag",
                summary: "Use Sensors and ROS2 to capture a bounded bag from a live topic set.",
                steps: [
                    GuidedFlowStep(title: "Choose Stream", detail: "Select a ROS image or LaserScan stream from Sensors."),
                    GuidedFlowStep(title: "Verify Health", detail: "Confirm timestamps, FPS, and transport health look sane."),
                    GuidedFlowStep(title: "Record 30s Bag", detail: "Trigger a bounded bag recording from THOR."),
                    GuidedFlowStep(title: "Inspect Output", detail: "Verify the bag appears in ROS2 Bags and Diagnostics."),
                ]
            ),
        ]
    }

    func guidedFlowProgressMap(flowIDs: [String]) async -> [String: GuidedFlowProgressRecord] {
        guard let db, !flowIDs.isEmpty else { return [:] }
        let records = (try? await db.reader.read { dbConn in
            try GuidedFlowProgressRecord
                .filter(flowIDs.contains(Column("flowID")))
                .fetchAll(dbConn)
        }) ?? []
        return Dictionary(uniqueKeysWithValues: records.map { ($0.flowID, $0) })
    }

    func setGuidedFlowProgress(
        flowID: String,
        status: GuidedFlowStatus,
        progress: Double
    ) async throws {
        guard let db else { return }

        let clampedProgress = min(max(progress, 0), 1)
        try await db.writer.write { dbConn in
            if var existing = try GuidedFlowProgressRecord
                .filter(Column("flowID") == flowID)
                .fetchOne(dbConn)
            {
                existing.status = status
                existing.progress = clampedProgress
                existing.updatedAt = Date()
                try existing.update(dbConn)
            } else {
                let record = GuidedFlowProgressRecord(
                    flowID: flowID,
                    status: status,
                    progress: clampedProgress
                )
                try record.insert(dbConn)
            }
        }
    }

    func resetGuidedFlowProgress(flowIDs: [String]) async throws {
        guard let db, !flowIDs.isEmpty else { return }
        try await db.writer.write { dbConn in
            _ = try GuidedFlowProgressRecord
                .filter(flowIDs.contains(Column("flowID")))
                .deleteAll(dbConn)
        }
    }

    func capabilityMatrix(for deviceID: Int64) -> CapabilityMatrix {
        capabilityMatrices[deviceID] ?? CapabilityMatrix(connectionMode: "unknown", features: [:])
    }

    func readinessReport(for deviceID: Int64) -> ReadinessReport {
        readinessReports[deviceID] ?? ReadinessReport(deviceID: deviceID, overall: .unknown, items: [])
    }

    func refreshAllFoundationState() async {
        for device in devices {
            guard let deviceID = device.id else { continue }
            await refreshFoundationState(for: deviceID)
        }
    }

    func refreshFoundationState(for deviceID: Int64) async {
        guard let device = devices.first(where: { $0.id == deviceID }) else { return }
        let snapshot = try? await latestSnapshot(for: deviceID)
        let state = connectionStates[deviceID]
        capabilityMatrices[deviceID] = buildCapabilityMatrix(device: device, snapshot: snapshot, state: state)
        readinessReports[deviceID] = buildReadinessReport(device: device, snapshot: snapshot, state: state)
    }

    func setupChecks(for device: Device) -> [SetupCheckResult] {
        let deviceID = device.id ?? 0
        let state = connectionStates[deviceID]
        let report = readinessReport(for: deviceID)

        var checks: [SetupCheckResult] = [
            SetupCheckResult(
                stage: "Reachability",
                status: readinessStatus(from: state?.status ?? .unknown),
                reason: reachabilityReason(for: state?.status ?? .unknown, device: device),
                actionLabel: doctorActionLabel(for: state?.status ?? .unknown),
                rawDetails: state?.failureReason
            ),
        ]

        checks.append(contentsOf: report.items.map {
            SetupCheckResult(
                stage: $0.title,
                status: $0.status,
                reason: $0.summary,
                actionLabel: actionLabel(for: $0.category, status: $0.status),
                rawDetails: $0.detail
            )
        })

        return checks
    }

    func enrollSimulatorDevices() async throws -> [Device] {
        appendEvent("Starting simulator enrollment")

        let checker = PrerequisiteChecker()
        let prereqs = await checker.runAll()
        guard prereqs.contains(where: { $0.name == "Docker" && $0.status == .pass }) else {
            throw FoundationWorkflowError.dockerUnavailable
        }

        try runLocalShell("docker compose up -d")

        let candidates: [(String, Int, Int)] = [
            ("Jetson Thor Sim", 2222, 8470),
            ("Jetson Orin Sim", 2223, 8471),
        ]

        var enrolled: [Device] = []
        for (name, sshPort, agentPort) in candidates {
            let device = try await ensureSimulatorDevice(
                name: name,
                sshPort: sshPort,
                agentPort: agentPort
            )
            enrolled.append(device)
        }

        for device in enrolled {
            try await connectDevice(device, directPort: device.hostname == "localhost" ? (device.displayName.contains("Orin") ? 8471 : 8470) : nil)
            if let deviceID = device.id {
                await refreshFoundationState(for: deviceID)
            }
        }

        if let first = enrolled.first?.id {
            selectedDeviceID = first
        }
        activeWorkspace = .devices
        selectedDetailTab = .overview
        appendEvent("Simulator enrollment completed")
        return enrolled
    }

    func loadDeployRecipes() async throws -> [DeployRecipe] {
        guard let db else { return DeployRecipe.builtinRecipes }
        var records = try await db.reader.read { dbConn in
            try DeployRecipeRecord.order(Column("name").asc).fetchAll(dbConn)
        }

        if records.isEmpty {
            for recipe in DeployRecipe.builtinRecipes {
                _ = try await saveDeployRecipe(recipe)
            }
            records = try await db.reader.read { dbConn in
                try DeployRecipeRecord.order(Column("name").asc).fetchAll(dbConn)
            }
        }

        let decoder = JSONDecoder()
        return records.compactMap { record in
            guard let data = record.recipeJSON.data(using: .utf8),
                  var recipe = try? decoder.decode(DeployRecipe.self, from: data)
            else { return nil }
            recipe.id = record.id
            recipe.updatedAt = record.updatedAt
            recipe.createdAt = record.createdAt
            return recipe
        }
    }

    func saveDeployRecipe(_ recipe: DeployRecipe) async throws -> DeployRecipe {
        guard let db else { return recipe }

        var stored = recipe
        stored.updatedAt = Date()
        if stored.id == nil {
            stored.createdAt = Date()
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(stored)
        let initialRecord = DeployRecipeRecord(
            id: stored.id,
            name: stored.name,
            recipeJSON: String(decoding: data, as: UTF8.self),
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt
        )

        let saved = try await db.writer.write { dbConn -> DeployRecipeRecord in
            let record = initialRecord
            if let id = record.id, try DeployRecipeRecord.fetchOne(dbConn, id: id) != nil {
                try record.update(dbConn)
                return try DeployRecipeRecord.fetchOne(dbConn, id: id) ?? record
            }
            try record.insert(dbConn)
            return try DeployRecipeRecord.fetchOne(dbConn, id: dbConn.lastInsertedRowID) ?? record
        }

        stored.id = saved.id
        appendEvent("Saved deploy recipe \(stored.name)")
        return stored
    }

    func recordRecipeRun(_ run: RecipeRun) async throws -> RecipeRun {
        guard let db else { return run }
        let encoder = JSONEncoder()
        let logJSON = String(decoding: try encoder.encode(run.logs), as: UTF8.self)
        let initialRecord = RecipeRunRecord(
            id: run.id,
            deviceID: run.deviceID,
            recipeID: run.recipeID,
            status: run.status,
            logJSON: logJSON,
            startedAt: run.startedAt,
            finishedAt: run.finishedAt
        )

        let saved = try await db.writer.write { dbConn -> RecipeRunRecord in
            let record = initialRecord
            if let id = record.id, try RecipeRunRecord.fetchOne(dbConn, id: id) != nil {
                try record.update(dbConn)
                return try RecipeRunRecord.fetchOne(dbConn, id: id) ?? record
            }
            try record.insert(dbConn)
            return try RecipeRunRecord.fetchOne(dbConn, id: dbConn.lastInsertedRowID) ?? record
        }

        var copy = run
        copy.id = saved.id
        appendEvent("Recorded recipe run for \(run.recipeName)")
        return copy
    }

    func recentRecipeRuns(for deviceID: Int64) async throws -> [RecipeRun] {
        guard let db else { return [] }
        let records = try await db.reader.read { dbConn in
            try RecipeRunRecord
                .filter(Column("deviceID") == deviceID)
                .order(Column("startedAt").desc)
                .limit(20)
                .fetchAll(dbConn)
        }

        let decoder = JSONDecoder()
        return records.compactMap { record in
            let logs = (try? decoder.decode([RecipeRunLogLine].self, from: Data(record.logJSON.utf8))) ?? []
            return RecipeRun(
                id: record.id,
                deviceID: record.deviceID ?? deviceID,
                recipeID: record.recipeID,
                recipeName: recipeName(for: record.recipeID),
                status: record.status,
                logs: logs,
                startedAt: record.startedAt,
                finishedAt: record.finishedAt
            )
        }
    }

    func saveLaunchProfile(_ profile: LaunchProfile, for deviceID: Int64?) async throws -> LaunchProfile {
        guard let db else { return profile }
        var stored = profile
        stored.updatedAt = Date()
        if stored.id == nil {
            stored.createdAt = Date()
        }

        let encoder = JSONEncoder()
        let json = String(decoding: try encoder.encode(stored), as: UTF8.self)
        let initialRecord = LaunchProfileRecord(
            id: stored.id,
            deviceID: deviceID,
            name: stored.name,
            configJSON: json,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt
        )

        let saved = try await db.writer.write { dbConn -> LaunchProfileRecord in
            let record = initialRecord
            if let id = record.id, try LaunchProfileRecord.fetchOne(dbConn, id: id) != nil {
                try record.update(dbConn)
                return try LaunchProfileRecord.fetchOne(dbConn, id: id) ?? record
            }
            try record.insert(dbConn)
            return try LaunchProfileRecord.fetchOne(dbConn, id: dbConn.lastInsertedRowID) ?? record
        }

        stored.id = saved.id
        appendEvent("Saved launch profile \(stored.name)")
        return stored
    }

    func loadLaunchProfiles(for deviceID: Int64?) async throws -> [LaunchProfile] {
        guard let db else { return [] }
        let records = try await db.reader.read { dbConn in
            if let deviceID {
                return try LaunchProfileRecord
                    .filter(Column("deviceID") == deviceID)
                    .order(Column("name").asc)
                    .fetchAll(dbConn)
            }
            return try LaunchProfileRecord.order(Column("name").asc).fetchAll(dbConn)
        }

        let decoder = JSONDecoder()
        return records.compactMap { record in
            guard let data = record.configJSON.data(using: .utf8),
                  var profile = try? decoder.decode(LaunchProfile.self, from: data)
            else { return nil }
            profile.id = record.id
            return profile
        }
    }

    func collectDiagnostics(for device: Device, sections: [String] = []) async throws -> URL {
        guard let deviceID = device.id else { throw FoundationWorkflowError.invalidDevice }
        guard let client = connector?.agentClient(for: deviceID) else { throw FoundationWorkflowError.deviceNotConnected }

        let archiveData = try await client.diagnosticsArchive(sectionSelection: sections)
        let folder = diagnosticsDirectory().appendingPathComponent(device.displayName.replacingOccurrences(of: " ", with: "-"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let stamp = DateFormatter.foundationArchiveStamp.string(from: Date())
        let archiveURL = folder.appendingPathComponent("thor-diagnostics-\(stamp).zip")
        try archiveData.write(to: archiveURL)

        let report = readinessReport(for: deviceID)
        let manifest = DiagnosticBundleManifest(
            deviceID: deviceID,
            deviceName: device.displayName,
            hostname: device.hostname,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            cliVersion: "thorctl 0.1.0",
            isSimulator: isSimulatorDevice(device),
            sections: sections.isEmpty ? report.items.map(\.title) : sections
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        let manifestURL = folder.appendingPathComponent("manifest-\(stamp).json")
        try manifestData.write(to: manifestURL)

        let summary = diagnosticsSummary(device: device, report: report, archiveURL: archiveURL)
        let summaryURL = folder.appendingPathComponent("SUMMARY-\(stamp).md")
        try summary.data(using: .utf8)?.write(to: summaryURL)

        if let db {
            let diagnosticRun = DiagnosticRunRecord(
                deviceID: deviceID,
                archivePath: archiveURL.path,
                manifestJSON: String(decoding: manifestData, as: UTF8.self)
            )
            try await db.writer.write { dbConn in
                let record = diagnosticRun
                try record.insert(dbConn)
            }
        }

        appendEvent("Collected diagnostics for \(device.displayName)")
        return archiveURL
    }

    func recentDiagnosticRuns(for deviceID: Int64) async throws -> [DiagnosticRunRecord] {
        guard let db else { return [] }
        return try await db.reader.read { dbConn in
            try DiagnosticRunRecord
                .filter(Column("deviceID") == deviceID)
                .order(Column("createdAt").desc)
                .limit(10)
                .fetchAll(dbConn)
        }
    }

    private func ensureSimulatorDevice(name: String, sshPort: Int, agentPort: Int) async throws -> Device {
        if let existing = devices.first(where: { $0.displayName == name && $0.hostname == "localhost" }) {
            let config = DeviceConfig(
                deviceID: existing.id ?? 0,
                sshUsername: "jetson",
                sshPort: sshPort,
                agentPort: agentPort,
                autoConnect: true,
                autoReconnect: true
            )
            try await connector?.saveDeviceConfig(config)
            try keychain.storePassword("jetson", for: existing.id ?? 0)
            return existing
        }

        let device = Device(
            displayName: name,
            hostname: "localhost",
            lastKnownIP: "127.0.0.1",
            environment: .demo
        )
        try await addDevice(device)
        guard let saved = devices.last, let deviceID = saved.id else {
            throw FoundationWorkflowError.invalidDevice
        }

        try keychain.storePassword("jetson", for: deviceID)
        let config = DeviceConfig(
            deviceID: deviceID,
            sshUsername: "jetson",
            sshPort: sshPort,
            agentPort: agentPort,
            autoConnect: true,
            autoReconnect: true
        )
        try await connector?.saveDeviceConfig(config)
        return saved
    }

    private func buildCapabilityMatrix(device: Device, snapshot: CompatibilitySnapshot?, state: ConnectionState?) -> CapabilityMatrix {
        let connected = state?.status == .connected
        let supported = snapshot?.supportStatus ?? .unknown
        let caps = decodedCapabilities(from: snapshot)
        let hasROS2 = snapshot?.ros2Presence == true || caps?.ros2Available == true
        let hasDocker = snapshot?.dockerVersion != nil || caps?.dockerVersion != nil
        let degradedStates = Set(caps?.degradedStates ?? [])
        let simulator = isSimulatorDevice(device)

        func gate(
            connectedRequired: Bool = true,
            available: Bool = true,
            degraded: Bool = false,
            unsupportedReason: String,
            setupReason: String = "Connect the device and rerun setup.",
            actionLabel: String? = "Open Setup"
        ) -> CapabilityGate {
            if supported == .unsupported {
                return CapabilityGate(state: .unsupported, reason: unsupportedReason, actionLabel: actionLabel)
            }
            if connectedRequired && !connected {
                return CapabilityGate(state: .needsSetup, reason: setupReason, actionLabel: actionLabel)
            }
            if !available {
                return CapabilityGate(state: .needsSetup, reason: setupReason, actionLabel: actionLabel)
            }
            if degraded {
                return CapabilityGate(state: .degraded, reason: "Available, but one or more prerequisites are degraded.", actionLabel: actionLabel)
            }
            return CapabilityGate(state: .supported, reason: "Ready")
        }

        let features: [String: CapabilityGate] = [
            DetailTab.overview.rawValue: gate(connectedRequired: false, available: true, unsupportedReason: "Overview is always available."),
            DetailTab.setup.rawValue: CapabilityGate(state: .supported, reason: "Setup and recovery tools are always available."),
            DetailTab.system.rawValue: gate(unsupportedReason: "System inspection is not supported for this target."),
            DetailTab.power.rawValue: gate(unsupportedReason: "Power controls are unavailable for this target."),
            DetailTab.hardware.rawValue: gate(unsupportedReason: "Hardware inspection is unavailable for this target."),
            DetailTab.sensors.rawValue: gate(
                available: hasROS2 || simulator,
                degraded: degradedStates.contains("no_bridged_camera"),
                unsupportedReason: "Sensors require ROS2 or a simulator-backed stream source.",
                setupReason: "Enable ROS2 or connect simulator sensor sources."
            ),
            DetailTab.docker.rawValue: gate(
                available: hasDocker,
                unsupportedReason: "Docker runtime is unavailable on this device.",
                setupReason: "Install or enable Docker on the device."
            ),
            DetailTab.ros2.rawValue: gate(
                available: hasROS2 || simulator,
                unsupportedReason: "ROS2 is unavailable on this device.",
                setupReason: "Install ROS2 or connect a simulator that exposes ROS2."
            ),
            DetailTab.anima.rawValue: gate(
                available: hasDocker,
                unsupportedReason: "ANIMA workflows require container runtime support.",
                setupReason: "Enable Docker before using ANIMA."
            ),
            DetailTab.files.rawValue: gate(unsupportedReason: "File operations are unavailable until the device is connected."),
            DetailTab.deploy.rawValue: gate(
                available: hasDocker,
                unsupportedReason: "Deploy recipes require Docker-ready runtime support.",
                setupReason: "Enable Docker and registry readiness before deploying."
            ),
            DetailTab.gpu.rawValue: gate(unsupportedReason: "GPU inspection is unavailable until the device is connected."),
            DetailTab.logs.rawValue: gate(unsupportedReason: "Logs are unavailable until the device is connected."),
            DetailTab.history.rawValue: gate(connectedRequired: false, available: true, unsupportedReason: "History is always available."),
            DetailTab.diagnostics.rawValue: gate(unsupportedReason: "Diagnostics collection is unavailable until the device is connected."),
        ]

        return CapabilityMatrix(
            deviceID: device.id,
            connectionMode: simulator ? "simulator" : "ssh_tunnel",
            features: features
        )
    }

    private func buildReadinessReport(device: Device, snapshot: CompatibilitySnapshot?, state: ConnectionState?) -> ReadinessReport {
        let caps = decodedCapabilities(from: snapshot)
        let connectionStatus = readinessStatus(from: state?.status ?? .unknown)
        let dockerReady = (snapshot?.dockerVersion != nil || caps?.dockerVersion != nil)
        let rosReady = snapshot?.ros2Presence == true || caps?.ros2Available == true || isSimulatorDevice(device)
        let sensorReady = rosReady || isSimulatorDevice(device)
        let registryReady = registryProfiles.isEmpty ? ReadinessStatus.warning : .ready
        let gpuStatus: ReadinessStatus = state?.status == .connected ? .ready : .unknown
        let storageStatus: ReadinessStatus = ((snapshot?.capabilitiesJSON?.isEmpty == false) || snapshot != nil) ? .ready : .unknown

        let items = [
            ReadinessItem(category: .connection, title: "Connection", status: connectionStatus, summary: reachabilityReason(for: state?.status ?? .unknown, device: device), detail: state?.failureReason),
            ReadinessItem(category: .agent, title: "Agent", status: snapshot != nil ? .ready : .warning, summary: snapshot == nil ? "No recent capability snapshot." : "Agent snapshot available.", detail: snapshot?.agentVersion),
            ReadinessItem(category: .ros2, title: "ROS2", status: rosReady ? .ready : .warning, summary: rosReady ? "ROS2 available." : "ROS2 missing or not detected.", detail: snapshot?.jetpackVersion),
            ReadinessItem(category: .sensors, title: "Sensors", status: sensorReady ? .ready : .warning, summary: sensorReady ? "At least one stream path is available." : "No sensor stream source detected.", detail: isSimulatorDevice(device) ? "Simulator stream catalog available." : nil),
            ReadinessItem(category: .docker, title: "Docker", status: dockerReady ? .ready : .warning, summary: dockerReady ? "Docker runtime detected." : "Docker is unavailable.", detail: snapshot?.dockerVersion),
            ReadinessItem(category: .registry, title: "Registry / Deploy", status: registryReady, summary: registryProfiles.isEmpty ? "No registry profiles configured yet." : "Registry profiles configured.", detail: registryProfiles.first?.endpointLabel),
            ReadinessItem(category: .gpu, title: "GPU / Thermal", status: gpuStatus, summary: gpuStatus == .ready ? "GPU telemetry available when connected." : "Connect the device to inspect GPU state.", detail: caps?.gpu.name),
            ReadinessItem(category: .storage, title: "Storage", status: storageStatus, summary: storageStatus == .ready ? "Storage and disk capability data present." : "Storage data not captured yet.", detail: snapshot?.osRelease),
        ]

        let overall = items.map(\.status).max(by: { $0.rank < $1.rank }) ?? .unknown
        return ReadinessReport(deviceID: device.id, overall: overall, items: items)
    }

    private func decodedCapabilities(from snapshot: CompatibilitySnapshot?) -> AgentCapabilitiesResponse? {
        guard let json = snapshot?.capabilitiesJSON,
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(AgentCapabilitiesResponse.self, from: data)
    }

    private func readinessStatus(from connection: ConnectionStatus) -> ReadinessStatus {
        switch connection {
        case .connected: .ready
        case .degraded: .warning
        case .disconnected, .authFailed, .hostKeyMismatch, .unreachable: .blocked
        case .unknown: .unknown
        }
    }

    private func reachabilityReason(for status: ConnectionStatus, device: Device) -> String {
        switch status {
        case .connected:
            return "Connected to \(device.hostname)."
        case .degraded:
            return "The device is reachable but one or more services are degraded."
        case .authFailed:
            return "SSH authentication failed."
        case .hostKeyMismatch:
            return "The saved SSH host key no longer matches."
        case .unreachable:
            return "Cannot reach \(device.hostname)."
        case .disconnected:
            return "The device is enrolled but not connected."
        case .unknown:
            return "Connectivity has not been checked yet."
        }
    }

    private func doctorActionLabel(for status: ConnectionStatus) -> String {
        switch status {
        case .connected: "Refresh"
        case .degraded, .disconnected, .unreachable: "Retry Connection"
        case .authFailed: "Update Credentials"
        case .hostKeyMismatch: "Review Host Key"
        case .unknown: "Run Checks"
        }
    }

    private func actionLabel(for category: ReadinessCategory, status: ReadinessStatus) -> String? {
        guard status != .ready else { return nil }
        return switch category {
        case .connection: "Retry Connection"
        case .agent: "Install Agent"
        case .ros2: "Open ROS2 Setup"
        case .sensors: "Open Sensors"
        case .docker: "Enable Docker"
        case .registry: "Configure Registry"
        case .gpu: "Reconnect Device"
        case .storage: "Refresh Snapshot"
        }
    }

    private func recipeName(for recipeID: Int64?) -> String {
        guard let recipeID else { return "Ad Hoc Recipe" }
        return (try? db?.reader.read { dbConn in
            try DeployRecipeRecord.fetchOne(dbConn, id: recipeID)?.name
        }) ?? "Recipe \(recipeID)"
    }

    private func diagnosticsDirectory() -> URL {
        DatabaseManager.supportDirectoryURL.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private func diagnosticsSummary(device: Device, report: ReadinessReport, archiveURL: URL) -> String {
        let lines = report.items.map { "- \($0.title): \($0.status.rawValue) — \($0.summary)" }
        return ([
            "# THOR Diagnostics",
            "",
            "- Device: \(device.displayName)",
            "- Host: \(device.hostname)",
            "- Archive: \(archiveURL.lastPathComponent)",
            "",
            "## Readiness",
        ] + lines).joined(separator: "\n")
    }

    private func runLocalShell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "-lc", command]
        if let cwd = projectRoot() {
            process.currentDirectoryURL = cwd
        }

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? command
            throw FoundationWorkflowError.commandFailed(message)
        }
    }

    private func projectRoot() -> URL? {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: (#filePath as NSString).deletingLastPathComponent)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent(),
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("docker-compose.yml").path) })
    }

    private func isSimulatorDevice(_ device: Device) -> Bool {
        device.hostname == "localhost" || device.hostname == "127.0.0.1"
    }
}

private extension DeployRecipe {
    static var builtinRecipes: [DeployRecipe] {
        [
            DeployRecipe(
                name: "System Health Check",
                summary: "Inspect disk, memory, services, and agent health before a session.",
                icon: "heart.text.square",
                prerequisites: [
                    DeployRecipePrerequisite(name: "Agent Reachable", command: "echo agent-ok", expectedSubstring: "agent-ok"),
                ],
                steps: [
                    DeployRecipeStep(type: .healthCheck, name: "Check disk space", command: "df -h /", timeout: 10),
                    DeployRecipeStep(type: .healthCheck, name: "Check memory", command: "free -h", timeout: 10),
                    DeployRecipeStep(type: .healthCheck, name: "List services", command: "systemctl list-units --type=service --state=running --no-pager | head -20", timeout: 10),
                ],
                readinessAssertions: [
                    DeployRecipeAssertion(name: "Filesystem ready", command: "df -h /", expectedSubstring: "/"),
                ]
            ),
            DeployRecipe(
                name: "Registry Pull Preflight",
                summary: "Verify runtime, then pull a container image with typed preflight and rollback.",
                icon: "shippingbox.circle",
                variables: [
                    DeployRecipeVariable(key: "IMAGE", label: "Image", defaultValue: "registry.demo.local:5443/demo/app:latest", required: true),
                ],
                prerequisites: [
                    DeployRecipePrerequisite(name: "Docker Installed", command: "docker --version", expectedSubstring: "Docker"),
                ],
                steps: [
                    DeployRecipeStep(type: .registryPreflight, name: "Inspect image reference", command: "printf '%s\n' '{{IMAGE}}'", timeout: 10),
                    DeployRecipeStep(type: .dockerPull, name: "Pull image", command: "docker pull {{IMAGE}}", timeout: 120),
                    DeployRecipeStep(type: .healthCheck, name: "Verify local image cache", command: "docker images --format '{{.Repository}}:{{.Tag}}' | grep -F '{{IMAGE}}'", timeout: 20),
                ],
                rollbackSteps: [
                    DeployRecipeStep(type: .dockerComposeDown, name: "Remove pulled image", command: "docker rmi {{IMAGE}}", timeout: 60, stopOnFailure: false),
                ]
            ),
            DeployRecipe(
                name: "ROS2 Session Bringup",
                summary: "Verify ROS2 discovery surfaces before recording bags or inspecting sensors.",
                icon: "point.3.connected.trianglepath.dotted",
                prerequisites: [
                    DeployRecipePrerequisite(name: "ROS2 Installed", command: "ros2 --version", expectedSubstring: "ros2"),
                ],
                steps: [
                    DeployRecipeStep(type: .ros2LaunchStart, name: "List nodes", command: "ros2 node list", timeout: 10, stopOnFailure: false),
                    DeployRecipeStep(type: .ros2LaunchStart, name: "List services", command: "ros2 service list", timeout: 10, stopOnFailure: false),
                    DeployRecipeStep(type: .ros2BagRecord, name: "Inspect topics", command: "ros2 topic list", timeout: 10, stopOnFailure: false),
                ],
                readinessAssertions: [
                    DeployRecipeAssertion(name: "Topics visible", command: "ros2 topic list", expectedSubstring: "/"),
                ]
            ),
        ]
    }
}

private extension DateFormatter {
    static let foundationArchiveStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}

enum FoundationWorkflowError: Error, LocalizedError {
    case dockerUnavailable
    case invalidDevice
    case deviceNotConnected
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .dockerUnavailable:
            return "Docker Desktop is not available. Start Docker Desktop before using the simulator path."
        case .invalidDevice:
            return "Device record is missing or invalid."
        case .deviceNotConnected:
            return "The device is not connected."
        case .commandFailed(let message):
            return "Local command failed: \(message)"
        }
    }
}
