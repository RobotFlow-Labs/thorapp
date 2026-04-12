import SwiftUI
import THORShared

struct ROS2InspectorView: View {
    let deviceID: Int64
    @Environment(AppState.self) private var appState

    @State private var nodes: [String] = []
    @State private var topics: [ROS2Topic] = []
    @State private var topicStats: [ROSTopicStats] = []
    @State private var services: [ROS2Service] = []
    @State private var graph: ROSGraphSnapshot?
    @State private var parameters: [ROSParameter] = []
    @State private var actions: [ROSActionDefinition] = []
    @State private var launches: [ROS2ProcessInfo] = []
    @State private var bags: [ROS2Bag] = []
    @State private var recordings: [ROS2ProcessInfo] = []
    @State private var launchProfiles: [LaunchProfile] = []

    @State private var selectedTab: ROS2WorkbenchTab = .graph
    @State private var selectedParameterNode = ""
    @State private var selectedActionName: String?
    @State private var actionGoalText = "{\n  \"speed\": 0.5\n}"
    @State private var bagTopicsInput = "/camera/image_raw /scan"
    @State private var launchDraft = LaunchProfileDraft()
    @State private var parameterEditor: ROSParameter?
    @State private var editedParameterValue = ""
    @State private var confirmingActionSend = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var selectedAction: ROSActionDefinition? {
        actions.first(where: { $0.name == selectedActionName }) ?? actions.first
    }

    private var topicStatsByName: [String: ROSTopicStats] {
        Dictionary(uniqueKeysWithValues: topicStats.map { ($0.topic, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            tabBar
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            panelContent
        }
        .task {
            await loadWorkbench()
        }
        .onChange(of: selectedParameterNode) { _, _ in
            Task { await loadParameters() }
        }
        .sheet(item: $parameterEditor) { parameter in
            NavigationStack {
                Form {
                    Section("Parameter") {
                        LabeledContent("Node", value: parameter.node)
                        LabeledContent("Name", value: parameter.name)
                        LabeledContent("Type", value: parameter.type)
                    }
                    Section("Value") {
                        TextField("Value", text: $editedParameterValue)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .navigationTitle("Set Parameter")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            parameterEditor = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            Task { await applyParameterChange(parameter) }
                        }
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 260)
        }
        .confirmationDialog(
            "Send ROS2 Action Goal",
            isPresented: $confirmingActionSend,
            titleVisibility: .visible
        ) {
            Button("Send Goal") {
                Task { await sendGoal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This writes to the robot runtime. Confirm before sending a goal to \(selectedAction?.name ?? "the selected action").")
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("ROS2 Workbench", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 15, weight: .semibold))
                Text("Inspect graph topology, browse topics and services, manage parameters, launch files, actions, and bags from one surface.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await loadWorkbench() }
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

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ROS2WorkbenchTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.label, systemImage: tab.icon)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedTab == tab ? Color.accentColor : Color(.secondarySystemFill).opacity(0.45))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedTab {
        case .graph:
            graphPanel
        case .topics:
            topicsPanel
        case .services:
            servicesPanel
        case .parameters:
            parametersPanel
        case .launches:
            launchesPanel
        case .bags:
            bagsPanel
        case .actions:
            actionsPanel
        }
    }

    private var graphPanel: some View {
        GroupBox("Graph") {
            if let graph {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        metadataChip("Nodes", value: "\(graph.nodes.count)")
                        metadataChip("Edges", value: "\(graph.edges.count)")
                        metadataChip("Captured", value: graph.capturedAt)
                        Spacer()
                    }

                    if graph.nodes.isEmpty {
                        emptyState("No ROS graph data available.")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Nodes")
                                .font(.system(size: 12, weight: .medium))
                            ForEach(graph.nodes) { node in
                                HStack {
                                    Text(node.name)
                                        .font(.system(size: 12, design: .monospaced))
                                    Spacer()
                                    Text(node.kind)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Divider()
                            Text("Edges")
                                .font(.system(size: 12, weight: .medium))
                            ForEach(graph.edges) { edge in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(edge.from) → \(edge.to)")
                                        .font(.system(size: 12, design: .monospaced))
                                    Text("\(edge.topic) [\(edge.messageType)]")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                emptyState("Graph snapshot not loaded yet.")
            }
        }
    }

    private var topicsPanel: some View {
        GroupBox("Topics") {
            if topics.isEmpty {
                emptyState("No ROS2 topics detected.")
            } else {
                VStack(spacing: 0) {
                    ForEach(topics) { topic in
                        let stats = topicStatsByName[topic.name]
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(topic.name)
                                    .font(.system(size: 12, design: .monospaced))
                                Text(topic.type)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Hz: \(stats?.hz.map { String(format: "%.1f", $0) } ?? "—")")
                                Text("Pub/Sub: \((stats?.publishers ?? 0))/\((stats?.subscribers ?? 0))")
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)

                        if topic.id != topics.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var servicesPanel: some View {
        GroupBox("Services") {
            if services.isEmpty {
                emptyState("No ROS2 services detected.")
            } else {
                VStack(spacing: 0) {
                    ForEach(services) { service in
                        HStack {
                            Text(service.name)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text(service.type)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        if service.id != services.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var parametersPanel: some View {
        GroupBox("Parameters") {
            VStack(alignment: .leading, spacing: 12) {
                if !nodes.isEmpty {
                    Picker("Node", selection: $selectedParameterNode) {
                        ForEach(nodes, id: \.self) { node in
                            Text(node).tag(node)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 320)
                }

                if parameters.isEmpty {
                    emptyState(selectedParameterNode.isEmpty ? "Select a node to inspect its parameters." : "No parameters returned for \(selectedParameterNode).")
                } else {
                    VStack(spacing: 0) {
                        ForEach(parameters) { parameter in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(parameter.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(parameter.value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(parameter.type)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if !parameter.readOnly {
                                    Button("Set…") {
                                        editedParameterValue = parameter.value
                                        parameterEditor = parameter
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)

                            if parameter.id != parameters.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var launchesPanel: some View {
        GroupBox("Launches") {
            VStack(alignment: .leading, spacing: 16) {
                launchProfileComposer

                Divider()

                Text("Saved Launch Profiles")
                    .font(.system(size: 12, weight: .medium))

                if launchProfiles.isEmpty {
                    emptyState("Save a launch profile to reuse package, launch file, args, and expected readiness signals.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(launchProfiles) { profile in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(profile.package) \(profile.launchFile)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    if !profile.arguments.isEmpty {
                                        Text("Args: \(profile.arguments.joined(separator: " "))")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Run") {
                                    Task { await runLaunchProfile(profile) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 8)
                            if profile.id != launchProfiles.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                Divider()

                Text("Active Launches")
                    .font(.system(size: 12, weight: .medium))

                if launches.isEmpty {
                    emptyState("No active launches.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(launches) { launch in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(launch.command)
                                        .font(.system(size: 11, design: .monospaced))
                                    Text("PID \(launch.pid) • \(launch.startedAt)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Stop") {
                                    Task { await stopLaunch(launch) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 8)
                            if launch.id != launches.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var bagsPanel: some View {
        GroupBox("Bags") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Topics to record", text: $bagTopicsInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Record 30s Bag") {
                        Task { await recordBoundedBag() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !recordings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Recordings")
                            .font(.system(size: 12, weight: .medium))
                        ForEach(recordings) { recording in
                            Text("PID \(recording.pid) • \(recording.command)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    Divider()
                }

                if bags.isEmpty {
                    emptyState("No bag files recorded yet.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(bags) { bag in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bag.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(bag.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(bag.sizeBytes.map(ByteCountFormatter.string) ?? "—")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            if bag.id != bags.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionsPanel: some View {
        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 12) {
                if actions.isEmpty {
                    emptyState("No ROS2 actions detected.")
                } else {
                    Picker("Action", selection: Binding(
                        get: { selectedActionName ?? actions.first?.name ?? "" },
                        set: { selectedActionName = $0 }
                    )) {
                        ForEach(actions) { action in
                            Text(action.name).tag(action.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 360)

                    if let selectedAction {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedAction.type)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let goalSchema = selectedAction.goalSchema, !goalSchema.isEmpty {
                                Text(goalSchema)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    TextEditor(text: $actionGoalText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 180)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }

                    Button("Send Goal") {
                        confirmingActionSend = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var launchProfileComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launch Profile Composer")
                .font(.system(size: 12, weight: .medium))

            HStack {
                TextField("Profile name", text: $launchDraft.name)
                TextField("Package", text: $launchDraft.package)
                TextField("Launch file", text: $launchDraft.launchFile)
            }
            .textFieldStyle(.roundedBorder)

            TextField("Arguments (space-separated)", text: $launchDraft.arguments)
                .textFieldStyle(.roundedBorder)

            TextField("Environment overrides (KEY=VALUE, comma-separated)", text: $launchDraft.environmentOverrides)
                .textFieldStyle(.roundedBorder)

            TextField("Expected readiness signals (comma-separated)", text: $launchDraft.expectedSignals)
                .textFieldStyle(.roundedBorder)

            Button("Save Launch Profile") {
                Task { await saveLaunchProfile() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func metadataChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill).opacity(0.45))
        .clipShape(.capsule)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func loadWorkbench() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let nodesResp = client.ros2Nodes()
            async let topicsResp = client.ros2Topics()
            async let servicesResp = client.ros2Services()
            async let graphResp = client.ros2Graph()
            async let topicStatsResp = client.ros2TopicStats()
            async let launchesResp = client.ros2Launches()
            async let bagsResp = client.ros2BagList()
            async let actionsResp = client.ros2Actions()
            async let savedProfiles = appState.loadLaunchProfiles(for: deviceID)

            let (
                nodesResult,
                topicsResult,
                servicesResult,
                graphResult,
                topicStatsResult,
                launchesResult,
                bagsResult,
                actionsResult,
                profiles
            ) = try await (
                nodesResp,
                topicsResp,
                servicesResp,
                graphResp,
                topicStatsResp,
                launchesResp,
                bagsResp,
                actionsResp,
                savedProfiles
            )

            nodes = nodesResult.nodes
            topics = topicsResult.topics
            services = servicesResult.services
            graph = graphResult.graph
            topicStats = topicStatsResult.topics
            launches = launchesResult.launches.filter { $0.category == "ros2_launch" || $0.command.contains("ros2 launch") }
            bags = bagsResult.bags
            recordings = bagsResult.recordings?.filter { $0.category == "ros2_bag" || $0.command.contains("ros2 bag") } ?? []
            actions = actionsResult.actions
            launchProfiles = profiles

            if selectedParameterNode.isEmpty {
                selectedParameterNode = graph?.nodes.first?.name ?? nodes.first ?? ""
            }
            if selectedActionName == nil {
                selectedActionName = actions.first?.name
            }

            await loadParameters()
            errorMessage = [
                nodesResult.error,
                topicsResult.error,
                servicesResult.error,
                actionsResult.error,
            ].compactMap { $0 }.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadParameters() async {
        guard !selectedParameterNode.isEmpty,
              let client = appState.connector?.agentClient(for: deviceID)
        else { return }

        do {
            let response = try await client.ros2Parameters(node: selectedParameterNode)
            parameters = response.parameters
            if let error = response.error {
                errorMessage = error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyParameterChange(_ parameter: ROSParameter) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        do {
            let response = try await client.ros2SetParameter(
                node: parameter.node,
                name: parameter.name,
                value: editedParameterValue
            )
            if let error = response.error {
                errorMessage = error
            } else {
                errorMessage = "Updated \(parameter.name) on \(parameter.node)."
            }
            parameterEditor = nil
            await loadParameters()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveLaunchProfile() async {
        do {
            let profile = LaunchProfile(
                name: launchDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                package: launchDraft.package.trimmingCharacters(in: .whitespacesAndNewlines),
                launchFile: launchDraft.launchFile.trimmingCharacters(in: .whitespacesAndNewlines),
                arguments: launchDraft.arguments.split(whereSeparator: { $0.isWhitespace }).map(String.init),
                environmentOverrides: launchDraft.environmentDictionary,
                expectedReadinessSignals: launchDraft.expectedSignals
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            guard !profile.name.isEmpty, !profile.package.isEmpty, !profile.launchFile.isEmpty else {
                throw ROS2WorkbenchError.invalidLaunchProfile
            }
            _ = try await appState.saveLaunchProfile(profile, for: deviceID)
            launchDraft = LaunchProfileDraft()
            launchProfiles = try await appState.loadLaunchProfiles(for: deviceID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runLaunchProfile(_ profile: LaunchProfile) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        do {
            let response = try await client.ros2Launch(
                package: profile.package,
                launchFile: profile.launchFile,
                arguments: profile.arguments,
                environment: profile.environmentOverrides
            )
            errorMessage = response.error ?? "Started \(profile.name) (PID \(response.pid ?? 0))."
            await loadWorkbench()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopLaunch(_ launch: ROS2ProcessInfo) async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        do {
            let response = try await client.ros2LaunchStop(pid: launch.pid)
            errorMessage = response.error ?? "Stopped launch \(launch.pid)."
            await loadWorkbench()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordBoundedBag() async {
        guard let client = appState.connector?.agentClient(for: deviceID) else { return }
        let topics = bagTopicsInput
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        do {
            let output = "/tmp/thor_bag_\(Int(Date().timeIntervalSince1970))"
            let response = try await client.ros2BagRecord(topics: topics, output: output)
            errorMessage = "Recording bag to \(output) for 30 seconds."
            try? await Task.sleep(for: .seconds(30))
            if let pid = response.pid {
                _ = try await client.ros2BagStop(pid: pid)
            }
            errorMessage = "Bag recording completed."
            await loadWorkbench()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendGoal() async {
        guard let client = appState.connector?.agentClient(for: deviceID),
              let selectedAction
        else { return }

        do {
            let response = try await client.ros2SendGoal(action: selectedAction.name, goal: actionGoalText)
            errorMessage = response.error ?? response.message ?? "Sent goal to \(selectedAction.name)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ROS2WorkbenchTab: String, CaseIterable {
    case graph
    case topics
    case services
    case parameters
    case launches
    case bags
    case actions

    var label: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .graph:
            "point.3.connected.trianglepath.dotted"
        case .topics:
            "arrow.left.arrow.right"
        case .services:
            "bolt.circle"
        case .parameters:
            "slider.horizontal.3"
        case .launches:
            "play.square"
        case .bags:
            "archivebox"
        case .actions:
            "scope"
        }
    }
}

private struct LaunchProfileDraft {
    var name = ""
    var package = ""
    var launchFile = ""
    var arguments = ""
    var environmentOverrides = ""
    var expectedSignals = ""

    var environmentDictionary: [String: String] {
        var values: [String: String] = [:]
        for pair in environmentOverrides.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return values
    }
}

private enum ROS2WorkbenchError: LocalizedError {
    case invalidLaunchProfile

    var errorDescription: String? {
        switch self {
        case .invalidLaunchProfile:
            return "Launch profile requires a name, package, and launch file."
        }
    }
}

private extension ByteCountFormatter {
    static func string(from bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
