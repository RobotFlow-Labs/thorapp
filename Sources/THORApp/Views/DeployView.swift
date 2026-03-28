import SwiftUI
import THORShared

struct DeployView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var profiles: [DeployProfile] = []
    @State private var showingNewProfile = false
    @State private var runningProfileID: String?
    @State private var executionLog: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
            }
            if profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
            if !executionLog.isEmpty {
                executionLogView
            }
        }
        .onAppear { loadBuiltinProfiles() }
        .sheet(isPresented: $showingNewProfile) {
            NewDeployProfileView { profile in
                profiles.append(profile)
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Label("Deploy Profiles", systemImage: "play.rectangle")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Button("New Profile", systemImage: "plus") {
                showingNewProfile = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No deploy profiles yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var profileList: some View {
        VStack(spacing: 0) {
            ForEach(profiles) { profile in
                profileRow(profile)
                if profile.id != profiles.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemFill).opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func profileRow(_ profile: DeployProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: profile.icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 13, weight: .medium))
                Text(profile.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if profile.steps.isEmpty {
                Text("No steps")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(profile.steps.count) step\(profile.steps.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await runProfile(profile) }
            } label: {
                if runningProfileID == profile.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(.borderless)
            .disabled(runningProfileID != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var executionLogView: some View {
        GroupBox("Execution Log") {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(executionLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(logLineColor(line))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Actions

    private func runProfile(_ profile: DeployProfile) async {
        guard let client = appState.connector?.agentClient(for: device.id ?? 0) else {
            errorMessage = "Device not connected"
            return
        }

        runningProfileID = profile.id
        executionLog = ["[\(timestamp())] Starting profile: \(profile.name)"]
        errorMessage = nil

        // Preflight checks
        for check in profile.preflightChecks {
            executionLog.append("[\(timestamp())] Preflight: \(check)")
            do {
                let result = try await client.exec(command: check, timeout: 10)
                if result.exitCode != 0 {
                    executionLog.append("[\(timestamp())] PREFLIGHT FAILED: \(result.stderr)")
                    errorMessage = "Preflight failed: \(check)"
                    runningProfileID = nil
                    return
                }
                executionLog.append("[\(timestamp())] Preflight OK")
            } catch {
                executionLog.append("[\(timestamp())] PREFLIGHT ERROR: \(error.localizedDescription)")
                runningProfileID = nil
                return
            }
        }

        // Execute steps
        for (index, step) in profile.steps.enumerated() {
            executionLog.append("[\(timestamp())] Step \(index + 1)/\(profile.steps.count): \(step.name)")
            do {
                let result = try await client.exec(command: step.command, timeout: step.timeout)
                if result.exitCode == 0 {
                    executionLog.append("[\(timestamp())] Step \(index + 1) OK")
                    if !result.stdout.isEmpty {
                        let preview = String(result.stdout.prefix(200))
                        executionLog.append("  → \(preview)")
                    }
                } else {
                    executionLog.append("[\(timestamp())] Step \(index + 1) FAILED (exit \(result.exitCode))")
                    if !result.stderr.isEmpty {
                        executionLog.append("  → \(result.stderr)")
                    }
                    if step.stopOnFailure {
                        errorMessage = "Deploy stopped at step \(index + 1): \(step.name)"
                        break
                    }
                }
            } catch {
                executionLog.append("[\(timestamp())] Step \(index + 1) ERROR: \(error.localizedDescription)")
                if step.stopOnFailure { break }
            }
        }

        executionLog.append("[\(timestamp())] Profile execution complete")
        runningProfileID = nil
    }

    private func loadBuiltinProfiles() {
        profiles = DeployProfile.builtins
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private func logLineColor(_ line: String) -> Color {
        if line.contains("FAILED") || line.contains("ERROR") { return .red }
        if line.contains("OK") { return .green }
        if line.contains("Preflight") || line.contains("Starting") { return .secondary }
        return .primary
    }
}

// MARK: - Deploy Profile Model

struct DeployProfile: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let preflightChecks: [String]
    let steps: [DeployStep]

    static var builtins: [DeployProfile] {
        [
            DeployProfile(
                id: "system-update",
                name: "System Health Check",
                description: "Check disk, memory, services, and agent status",
                icon: "heart.text.square",
                preflightChecks: [],
                steps: [
                    DeployStep(name: "Check disk space", command: "df -h /", timeout: 10),
                    DeployStep(name: "Check memory", command: "free -h", timeout: 10),
                    DeployStep(name: "Check uptime", command: "uptime", timeout: 10),
                    DeployStep(name: "List running services", command: "systemctl list-units --type=service --state=running --no-pager | head -20", timeout: 10),
                ]
            ),
            DeployProfile(
                id: "docker-cleanup",
                name: "Docker Cleanup",
                description: "Remove stopped containers and dangling images",
                icon: "trash",
                preflightChecks: ["docker --version"],
                steps: [
                    DeployStep(name: "Remove stopped containers", command: "docker container prune -f", timeout: 30),
                    DeployStep(name: "Remove dangling images", command: "docker image prune -f", timeout: 30),
                    DeployStep(name: "Show disk usage", command: "docker system df", timeout: 10),
                ]
            ),
            DeployProfile(
                id: "ros2-check",
                name: "ROS2 Environment Check",
                description: "Verify ROS2 installation and list active nodes/topics",
                icon: "point.3.connected.trianglepath.dotted",
                preflightChecks: ["ros2 --version"],
                steps: [
                    DeployStep(name: "ROS2 version", command: "ros2 --version", timeout: 10),
                    DeployStep(name: "List nodes", command: "ros2 node list", timeout: 10, stopOnFailure: false),
                    DeployStep(name: "List topics", command: "ros2 topic list", timeout: 10, stopOnFailure: false),
                    DeployStep(name: "List services", command: "ros2 service list", timeout: 10, stopOnFailure: false),
                ]
            ),
        ]
    }
}

struct DeployStep {
    let name: String
    let command: String
    let timeout: Int
    let stopOnFailure: Bool

    init(name: String, command: String, timeout: Int = 30, stopOnFailure: Bool = true) {
        self.name = name
        self.command = command
        self.timeout = timeout
        self.stopOnFailure = stopOnFailure
    }
}

// MARK: - New Profile Sheet

private struct NewDeployProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var steps: [EditableStep] = [EditableStep()]
    let onSave: (DeployProfile) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description)
                }
                Section("Steps") {
                    ForEach($steps) { $step in
                        HStack {
                            TextField("Step name", text: $step.name)
                                .frame(width: 120)
                            TextField("Command", text: $step.command)
                        }
                    }
                    Button("Add Step") {
                        steps.append(EditableStep())
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || steps.allSatisfy { $0.command.isEmpty })
            }
            .padding(20)
        }
        .frame(width: 500, height: 400)
    }

    private func save() {
        let deploySteps = steps
            .filter { !$0.command.isEmpty }
            .map { DeployStep(name: $0.name.isEmpty ? $0.command : $0.name, command: $0.command) }

        let profile = DeployProfile(
            id: UUID().uuidString,
            name: name,
            description: description,
            icon: "play.rectangle",
            preflightChecks: [],
            steps: deploySteps
        )
        onSave(profile)
        dismiss()
    }
}

private struct EditableStep: Identifiable {
    let id = UUID()
    var name = ""
    var command = ""
}
