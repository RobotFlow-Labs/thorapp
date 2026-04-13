import AppKit
import SwiftUI
import THORShared

struct JetsonThorQuickStartView: View {
    let device: Device?
    var showsBackButton = false

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot = JetsonThorHostSnapshot.empty
    @State private var progressRecords: [String: GuidedFlowProgressRecord] = [:]
    @State private var sshUsername = "nvidia"
    @State private var identityPath: String?
    @State private var message: String?

    private let support = JetsonThorQuickStartSupport()

    private struct StepDescriptor: Identifiable {
        let id: String
        let title: String
        let summary: String
        let detail: String
        let actionLabel: String
    }

    private var flowBaseID: String {
        "jetson-agx-thor-headless-first-boot"
    }

    private var steps: [StepDescriptor] {
        [
            StepDescriptor(
                id: "\(flowBaseID)/uefi",
                title: "UEFI / BSP Install",
                summary: "Use Debug-USB, boot the USB installer, flash NVMe, let UEFI auto-update, then remove the USB stick.",
                detail: "Thor Debug-USB exposes multiple `/dev/cu.usbserial-*` ports on macOS. Factory UEFI 38.0.0 is safest at 242x61 and 9600 baud.",
                actionLabel: "Open UEFI Console"
            ),
            StepDescriptor(
                id: "\(flowBaseID)/oem-config",
                title: "OEM-config over USB-C",
                summary: "Move the cable to Thor USB-C 5a after the NVMe boot and finish the text-mode first-boot setup.",
                detail: "After the installer finishes, the CUI setup moves off the Debug-USB path and appears as `/dev/cu.usbmodem*` on the regular USB-C data port.",
                actionLabel: "Open OEM-config Console"
            ),
            StepDescriptor(
                id: "\(flowBaseID)/usb-ssh",
                title: "First SSH over USB Tether",
                summary: "Use the built-in USB-Ethernet gadget path instead of guessing the LAN IP.",
                detail: "Thor should come up at `192.168.55.1` and your Mac should get `192.168.55.100`. This is the recommended first SSH path even if the RJ45 cable is not in use.",
                actionLabel: "Open USB SSH"
            ),
            StepDescriptor(
                id: "\(flowBaseID)/bootstrap",
                title: "Bootstrap SSH Keys + Sudo",
                summary: "Push a public key, enable passwordless sudo, and make agent install / package deploy flows non-fragile.",
                detail: "THOR vendors a repo-owned bootstrap helper so this no longer depends on a private local skill path. If no SSH key is present, THOR will offer to generate one first, then continue with bootstrap.",
                actionLabel: "Run Bootstrap Helper"
            ),
            StepDescriptor(
                id: "\(flowBaseID)/jetpack",
                title: "JetPack / Docker Readiness",
                summary: "Install `nvidia-jetpack`, verify Docker, then return to THOR’s setup doctor and install the THOR agent.",
                detail: "The USB-stick BSP install is not the full post-install environment. Finish JetPack, confirm Docker, then use THOR’s regular agent install and readiness board.",
                actionLabel: "Run JetPack Install"
            ),
        ]
    }

    private var completedSteps: Int {
        steps.filter { status(for: $0) == .completed }.count
    }

    private var progressValue: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(completedSteps) / Double(steps.count)
    }

    private var recommendedPublicKey: String? {
        snapshot.publicKeyCandidates.first(where: { $0.recommended })?.path
    }

    private var resolvedUsername: String {
        let trimmed = sshUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "nvidia" : trimmed
    }

    private var effectiveIdentityPath: String? {
        if let identityPath, !identityPath.isEmpty {
            return identityPath
        }
        guard let recommendedPublicKey else { return nil }
        let privateKeyPath = recommendedPublicKey.replacingOccurrences(of: ".pub", with: "")
        return FileManager.default.fileExists(atPath: privateKeyPath) ? privateKeyPath : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            hostDetection
            progressCard
            ForEach(steps) { step in
                stepCard(step)
            }
            resourcesCard
        }
        .task(id: device?.id) {
            await refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Jetson AGX Thor Headless Quick Start", systemImage: "sparkles.tv")
                    .font(.system(size: 16, weight: .semibold))
                Text("Bring up a brand-new Thor from macOS over Debug-USB, OEM-config, and USB tether without leaving THOR’s setup flow.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if showsBackButton {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var hostDetection: some View {
        GroupBox("Host Detection") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First-Boot Username")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("nvidia", text: $sshUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Text("THOR uses this username for USB SSH, bootstrap, and JetPack install commands.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Refresh Host State") {
                        Task { await refresh() }
                    }
                    .buttonStyle(.bordered)
                }

                detectionRow(
                    title: "Debug-USB serial",
                    value: serialValue(for: snapshot.debugSerialCandidates),
                    ok: !snapshot.debugSerialCandidates.isEmpty,
                    detail: snapshot.debugSerialCandidates.isEmpty
                        ? "Connect the Mac to Thor Debug-USB port 8."
                        : "\(snapshot.debugSerialCandidates.count) usbserial device(s) visible. THOR will open the second one unless you override it."
                )

                detectionRow(
                    title: "OEM-config serial",
                    value: serialValue(for: snapshot.oemConfigCandidates),
                    ok: !snapshot.oemConfigCandidates.isEmpty,
                    detail: snapshot.oemConfigCandidates.isEmpty
                        ? "Move the cable to Thor USB-C 5a after the installer finishes."
                        : "Use the first usbmodem device at 115200 baud."
                )

                detectionRow(
                    title: "USB tether",
                    value: snapshot.usbTetherDetected ? snapshot.usbTetherHostAddresses.joined(separator: ", ") : "No 192.168.55.x host address yet",
                    ok: snapshot.usbTetherDetected,
                    detail: "Thor usually exposes `192.168.55.1` and gives the Mac a `192.168.55.x` address."
                )

                detectionRow(
                    title: "Public key",
                    value: recommendedPublicKey ?? "No public key found",
                    ok: recommendedPublicKey != nil,
                    detail: recommendedPublicKey == nil
                        ? "Create or import an SSH key before running the bootstrap helper. THOR can generate one for you."
                        : "The bootstrap helper will append this key to `authorized_keys`."
                )
            }
        }
    }

    private var progressCard: some View {
        GroupBox("Flow Progress") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Resume where you stopped.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Progress") {
                        Task { await resetProgress() }
                    }
                    .buttonStyle(.bordered)
                }

                ProgressView(value: progressValue)
                    .tint(.accentColor)

                Text("\(completedSteps) of \(steps.count) steps completed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(detectionHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func stepCard(_ step: StepDescriptor) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(step.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusBadge(status(for: step))
                }

                Text(step.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(step.actionLabel) {
                        Task { await runAction(for: step) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(command(for: step) == nil)

                    if let command = command(for: step) {
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            message = "Copied command for \(step.title)."
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(status(for: step) == .completed ? "Mark Not Done" : "Mark Done") {
                        Task { await toggleCompletion(for: step) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } label: {
            EmptyView()
        }
    }

    private var resourcesCard: some View {
        GroupBox("Runbooks and References") {
            HStack(spacing: 12) {
                Button("Open THOR Runbook") {
                    openQuickStartDoc()
                }
                .buttonStyle(.bordered)

                Button("Open NVIDIA Quick Start") {
                    if let url = URL(string: "https://docs.nvidia.com/jetson/agx-thor-devkit/user-guide/latest/quick_start.html") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Button("Open UEFI 38.0.0 Note") {
                    if let url = URL(string: "https://docs.nvidia.com/jetson/agx-thor-devkit/user-guide/latest/twa_headless_on_uefi-38-0-0.html") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }

    private func detectionRow(title: String, value: String, ok: Bool, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ok ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.leading, 17)
        }
    }

    private func statusBadge(_ status: GuidedFlowStatus) -> some View {
        Text(statusLabel(for: status))
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(for: status).opacity(0.16))
            .foregroundStyle(statusColor(for: status))
            .clipShape(.capsule)
    }

    private func status(for step: StepDescriptor) -> GuidedFlowStatus {
        progressRecords[step.id]?.status ?? .notStarted
    }

    private func statusLabel(for status: GuidedFlowStatus) -> String {
        switch status {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        }
    }

    private func statusColor(for status: GuidedFlowStatus) -> Color {
        switch status {
        case .notStarted: .secondary
        case .inProgress: .orange
        case .completed: .green
        }
    }

    private func refresh() async {
        snapshot = support.snapshot()
        progressRecords = await appState.guidedFlowProgressMap(flowIDs: steps.map(\.id))

        if let deviceID = device?.id {
            let config = await appState.deviceConfig(for: deviceID)
            sshUsername = config.sshUsername
            identityPath = appState.keychain.sshKeyPath(for: deviceID)
        } else if identityPath == nil {
            identityPath = effectiveIdentityPath
        }
    }

    private func command(for step: StepDescriptor) -> String? {
        switch step.id {
        case "\(flowBaseID)/uefi":
            if let helper = helperScript(named: "thor_serial.sh") {
                return "/bin/bash \(shellQuoted(helper)) uefi"
            }
            guard let path = snapshot.debugSerialCandidates.first(where: { $0.recommended })?.path else {
                return nil
            }
            return JetsonThorQuickStartSupport.uefiConsoleCommand(serialPath: path)

        case "\(flowBaseID)/oem-config":
            if let helper = helperScript(named: "thor_serial.sh") {
                return "/bin/bash \(shellQuoted(helper)) oem-config"
            }
            guard let path = snapshot.oemConfigCandidates.first(where: { $0.recommended })?.path else {
                return nil
            }
            return JetsonThorQuickStartSupport.oemConfigConsoleCommand(serialPath: path)

        case "\(flowBaseID)/usb-ssh":
            return JetsonThorQuickStartSupport.usbSSHCommand(
                username: resolvedUsername,
                identityPath: effectiveIdentityPath
            )

        case "\(flowBaseID)/bootstrap":
            guard let helper = helperScript(named: "bootstrap_ssh.sh") else {
                return JetsonThorQuickStartSupport.sshKeyGenerationCommand()
            }
            if let recommendedPublicKey {
                return JetsonThorQuickStartSupport.bootstrapHelperCommand(
                    scriptPath: helper,
                    target: "\(resolvedUsername)@192.168.55.1",
                    publicKeyPath: recommendedPublicKey
                )
            }
            return JetsonThorQuickStartSupport.sshKeyGenerationCommand()

        case "\(flowBaseID)/jetpack":
            return JetsonThorQuickStartSupport.jetPackInstallCommand(
                username: resolvedUsername,
                identityPath: effectiveIdentityPath
            )

        default:
            return nil
        }
    }

    private func runAction(for step: StepDescriptor) async {
        guard let command = command(for: step) else {
            message = "That action is not available yet on this Mac."
            return
        }

        try? await appState.setGuidedFlowProgress(flowID: step.id, status: .inProgress, progress: 0.5)
        progressRecords = await appState.guidedFlowProgressMap(flowIDs: steps.map(\.id))
        TerminalLauncher.openCommand(command)
        message = "Opened \(step.title) in your terminal."
    }

    private func toggleCompletion(for step: StepDescriptor) async {
        let currentStatus = status(for: step)
        let nextStatus: GuidedFlowStatus = currentStatus == .completed ? .notStarted : .completed
        let progress = nextStatus == .completed ? 1.0 : 0.0
        try? await appState.setGuidedFlowProgress(flowID: step.id, status: nextStatus, progress: progress)
        progressRecords = await appState.guidedFlowProgressMap(flowIDs: steps.map(\.id))
    }

    private func resetProgress() async {
        try? await appState.resetGuidedFlowProgress(flowIDs: steps.map(\.id))
        progressRecords = [:]
        message = "Cleared saved headless bring-up progress."
    }

    private func helperScript(named name: String) -> String? {
        let candidates = [
            Bundle.main.resourcePath.map { "\($0)/jetson-thor/\(name)" },
            ProcessInfo.processInfo.environment["THOR_JETSON_HELPERS_DIR"].map { "\($0)/\(name)" },
            FileManager.default.currentDirectoryPath + "/Scripts/jetson-thor/\(name)",
        ]

        return candidates
            .compactMap { $0 }
            .first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func openQuickStartDoc() {
        let candidates = [
            Bundle.main.resourcePath.map { "\($0)/setup/jetson-agx-thor-headless-quickstart.md" },
            FileManager.default.currentDirectoryPath + "/docs/setup/jetson-agx-thor-headless-quickstart.md",
        ]

        if let path = candidates
            .compactMap({ $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0) })
        {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            message = "The local runbook is not bundled in this build."
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private var detectionHint: String {
        var parts: [String] = []

        if snapshot.debugSerialCandidates.isEmpty {
            parts.append("no Debug-USB serial detected")
        } else {
            parts.append("\(snapshot.debugSerialCandidates.count) Debug-USB serial(s)")
        }

        if snapshot.oemConfigCandidates.isEmpty {
            parts.append("no OEM-config usbmodem detected")
        } else {
            parts.append("\(snapshot.oemConfigCandidates.count) OEM-config serial(s)")
        }

        if snapshot.usbTetherDetected {
            parts.append("USB tether online")
        } else {
            parts.append("USB tether not seen")
        }

        if recommendedPublicKey == nil {
            parts.append("no SSH key found")
        }

        return parts.joined(separator: " • ")
    }

    private func serialValue(for candidates: [JetsonThorSerialCandidate]) -> String {
        guard let recommended = candidates.first(where: { $0.recommended })?.path else {
            return "Not detected"
        }

        if candidates.count > 1 {
            return "\(recommended) (\(candidates.count) detected)"
        }

        return recommended
    }
}
