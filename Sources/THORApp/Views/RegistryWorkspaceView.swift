import AppKit
import SwiftUI
import THORShared

struct RegistryWorkspaceView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedProfileID: Int64?
    @State private var selectedDeviceIDs: Set<Int64> = []
    @State private var draft = RegistryProfile(displayName: "", host: "")
    @State private var passwordInput = ""
    @State private var testImage = ""
    @State private var validationReport: RegistryValidationReport?
    @State private var deviceApplyResults: [Int64: DeviceRegistryApplyResponse] = [:]
    @State private var deviceValidationResults: [Int64: DeviceRegistryValidationResponse] = [:]
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isTrusting = false
    @State private var isApplyingToDevices = false
    @State private var isRunningDevicePreflight = false
    @State private var hasStoredPassword = false

    private var selectedProfile: RegistryProfile? {
        appState.registryProfiles.first(where: { $0.id == selectedProfileID })
    }

    private var connectedDeviceIDs: Set<Int64> {
        Set(
            appState.devices.compactMap { device in
                guard let id = device.id, appState.connectionStatus(for: id) == .connected else { return nil }
                return id
            }
        )
    }

    private var selectedDevices: [Device] {
        appState.devices.filter { device in
            guard let id = device.id else { return false }
            return selectedDeviceIDs.contains(id)
        }
    }

    private var macTrustStatus: RegistryValidationStatus {
        guard draft.scheme == .https else { return .pass }
        guard let path = draft.caCertificatePath else { return .warning }
        switch appState.registryCertificateService.trustState(for: URL(fileURLWithPath: path)) {
        case .trusted:
            return .pass
        case .untrusted:
            return .warning
        case .missing:
            return .fail
        }
    }

    private var credentialStatus: RegistryValidationStatus {
        guard let username = draft.username, !username.isEmpty else { return .pass }
        return hasStoredPassword || !passwordInput.isEmpty ? .pass : .warning
    }

    private var deviceRolloutStatus: RegistryValidationStatus {
        let statuses = deviceValidationResults.values.map(\.status)
        if statuses.contains(.fail) {
            return .fail
        }
        if statuses.contains(.warning) {
            return .warning
        }
        if !deviceApplyResults.isEmpty || !deviceValidationResults.isEmpty {
            return .pass
        }
        return .unknown
    }

    private var lastMacValidationStatus: RegistryValidationStatus {
        validationReport?.status ?? selectedProfile?.lastValidationStatus ?? .unknown
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .task {
            try? await appState.loadDevices()
            if selectedProfileID == nil {
                selectedProfileID = appState.registryProfiles.first?.id
                loadDraftFromSelection()
            }
        }
        .onChange(of: selectedProfileID) { _, _ in
            loadDraftFromSelection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Registries", systemImage: "shippingbox.circle")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    selectedProfileID = nil
                    draft = RegistryProfile(displayName: "", host: "")
                    passwordInput = ""
                    validationReport = nil
                    deviceApplyResults = [:]
                    deviceValidationResults = [:]
                    errorMessage = nil
                    hasStoredPassword = false
                    selectedDeviceIDs = connectedDeviceIDs
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Registry Profile")
            }

            List(selection: $selectedProfileID) {
                ForEach(appState.registryProfiles) { profile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                        Text(profile.endpointLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .tag(profile.id)
                }
            }
            .listStyle(.sidebar)

            if let message = errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                setupChecklistSection
                profileForm
                certificateSection
                validationSection
                deviceRolloutSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.id == nil ? "New Registry Profile" : draft.displayName)
                    .font(.system(size: 20, weight: .semibold))
                Text(draft.endpointLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Use this workspace to trust the registry on your Mac, apply it to Jetsons, and run a pull-style preflight before deploy.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let selectedProfile, let id = selectedProfile.id {
                Button("Clear Password") {
                    appState.clearRegistryPassword(for: id)
                    hasStoredPassword = false
                    passwordInput = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasStoredPassword)
            }
            if let selectedProfile {
                Button("Delete", role: .destructive) {
                    Task { await deleteProfile(selectedProfile) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button("Save") {
                Task { await saveProfile() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var setupChecklistSection: some View {
        GroupBox("Setup Checklist") {
            VStack(alignment: .leading, spacing: 10) {
                checklistRow(
                    "Profile saved",
                    status: draft.id == nil ? .warning : .pass,
                    detail: draft.id == nil ? "Save the registry profile first so THOR can reuse it." : "Registry profile is stored in THOR."
                )
                checklistRow(
                    "Certificate imported",
                    status: draft.scheme == .http ? .pass : (draft.caCertificatePath == nil ? .warning : .pass),
                    detail: draft.scheme == .http
                        ? "HTTP mode does not require a CA certificate."
                        : (draft.caCertificatePath == nil ? "Import the registry CA if this is a private or lab registry." : "A registry certificate is attached to this profile.")
                )
                checklistRow(
                    "Trusted on this Mac",
                    status: macTrustStatus,
                    detail: macTrustStatus == .pass ? "macOS trust is ready for local validation." : "Install trust into Keychain to avoid TLS failures on this Mac."
                )
                checklistRow(
                    "Credentials stored",
                    status: credentialStatus,
                    detail: credentialStatus == .pass ? "Credential requirements are satisfied for this profile." : "Store the password in Keychain so THOR can validate and apply auth."
                )
                checklistRow(
                    "Device rollout",
                    status: deviceRolloutStatus,
                    detail: deviceRolloutStatus == .unknown ? "Apply the profile to one or more connected Jetsons." : "Latest Jetson rollout/preflight status is shown below."
                )
                checklistRow(
                    "Mac validation",
                    status: lastMacValidationStatus,
                    detail: lastMacValidationStatus == .unknown ? "Run Mac validation before the demo." : "Latest Mac-side registry validation is recorded."
                )
            }
        }
    }

    private var profileForm: some View {
        GroupBox("Profile") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Display Name", text: $draft.displayName)
                HStack {
                    TextField("Registry Host", text: $draft.host)
                    TextField("Port", value: $draft.port, format: .number)
                        .frame(width: 90)
                    Picker("Scheme", selection: $draft.scheme) {
                        ForEach(RegistryScheme.allCases, id: \.self) { scheme in
                            Text(scheme.rawValue.uppercased()).tag(scheme)
                        }
                    }
                    .frame(width: 120)
                }
                HStack {
                    TextField("Username (optional)", text: Binding(
                        get: { draft.username ?? "" },
                        set: { draft.username = $0.isEmpty ? nil : $0 }
                    ))
                    SecureField(hasStoredPassword && passwordInput.isEmpty ? "Password saved in Keychain" : "Password", text: $passwordInput)
                }
                TextField("Repository Namespace (optional)", text: $draft.repositoryNamespace)
            }
        }
    }

    private var certificateSection: some View {
        GroupBox("Certificate Trust") {
            VStack(alignment: .leading, spacing: 10) {
                if let path = draft.caCertificatePath {
                    trustStateRow(for: path)
                    if let name = draft.caCertificateCommonName {
                        infoRow("Common Name", value: name)
                    }
                    if let issuer = draft.caCertificateIssuer {
                        infoRow("Issuer", value: issuer)
                    }
                    if let fingerprint = draft.caCertificateFingerprintSHA256 {
                        infoRow("SHA-256", value: fingerprint)
                    }
                    if let expiry = draft.caCertificateExpiresAt {
                        infoRow("Expires", value: expiry.formatted(date: .abbreviated, time: .omitted))
                    }
                } else {
                    Text("No custom CA imported yet.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }

                HStack {
                    Button("Import Certificate") {
                        importCertificate()
                    }
                    .buttonStyle(.bordered)

                    Button(isTrusting ? "Trusting..." : "Trust on This Mac") {
                        Task { await installTrust() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.caCertificatePath == nil || isTrusting)
                }
            }
        }
    }

    private var validationSection: some View {
        GroupBox("Mac Validation") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let status = selectedProfile?.lastValidationStatus, selectedProfile?.lastValidatedAt != nil {
                        Label(status.rawValue.capitalized, systemImage: statusIcon(status))
                            .foregroundStyle(statusColor(status))
                    }

                    Spacer()

                    Button("Run Validation") {
                        Task { await runValidation() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.id == nil)
                }

                if let report = validationReport {
                    ForEach(report.stages) { stage in
                        validationStageRow(name: stage.name, status: stage.status, message: stage.message)
                    }
                } else if let profile = selectedProfile, let message = profile.lastValidationMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run validation to check trust, reachability, and authentication readiness on this Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var deviceRolloutSection: some View {
        GroupBox("Jetson Rollout & Preflight") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select connected Jetsons, apply registry trust/auth, then run a device-side preflight before Docker pull or ANIMA deploy.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if appState.devices.isEmpty {
                    Text("No devices are enrolled in THOR yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.devices) { device in
                            if let id = device.id {
                                Toggle(isOn: Binding(
                                    get: { selectedDeviceIDs.contains(id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedDeviceIDs.insert(id)
                                        } else {
                                            selectedDeviceIDs.remove(id)
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(device.displayName)
                                                .font(.system(size: 13, weight: .medium))
                                            statusBadge(appState.connectionStatus(for: id).rawValue.capitalized, color: appState.connectionStatus(for: id) == .connected ? .green : .secondary)
                                            if let validation = deviceValidationResults[id] {
                                                statusBadge(validation.status.rawValue.capitalized, color: statusColor(validation.status))
                                            } else if let apply = deviceApplyResults[id] {
                                                statusBadge(apply.ready ? "Applied" : "Follow-up", color: apply.ready ? .green : .orange)
                                            }
                                        }

                                        Text(device.hostname)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)

                                        if let apply = deviceApplyResults[id], !apply.message.isEmpty {
                                            Text(apply.message)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        } else if let validation = deviceValidationResults[id], let stage = validation.stages.first(where: { $0.status != .pass }) ?? validation.stages.first {
                                            Text(stage.message)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(appState.connectionStatus(for: id) != .connected)
                            }
                        }
                    }
                }

                HStack {
                    TextField("Optional test image for device preflight", text: $testImage)
                    Button(isApplyingToDevices ? "Applying..." : "Apply to Selected Jetsons") {
                        Task { await applyToSelectedDevices() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.id == nil || selectedDeviceIDs.isEmpty || isApplyingToDevices)

                    Button(isRunningDevicePreflight ? "Checking..." : "Run Device Preflight") {
                        Task { await runDevicePreflight() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.id == nil || selectedDeviceIDs.isEmpty || isRunningDevicePreflight)
                }

                if !deviceValidationResults.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(selectedDevices) { device in
                            if let id = device.id, let validation = deviceValidationResults[id] {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(device.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                    ForEach(validation.stages) { stage in
                                        validationStageRow(name: stage.name, status: stage.status, message: stage.message)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func checklistRow(_ title: String, status: RegistryValidationStatus, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIcon(status))
                .foregroundStyle(statusColor(status))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func validationStageRow(name: String, status: RegistryValidationStatus, message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon(status))
                .foregroundStyle(statusColor(status))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func loadDraftFromSelection() {
        guard let selectedProfile else {
            hasStoredPassword = false
            selectedDeviceIDs = connectedDeviceIDs
            deviceApplyResults = [:]
            deviceValidationResults = [:]
            return
        }
        draft = selectedProfile
        passwordInput = ""
        validationReport = nil
        deviceApplyResults = [:]
        deviceValidationResults = [:]
        hasStoredPassword = selectedProfile.id.flatMap { appState.keychain.registryPassword(for: $0) } != nil
        selectedDeviceIDs = connectedDeviceIDs
    }

    private func saveProfile() async {
        isSaving = true
        errorMessage = nil
        do {
            let saved = try await appState.saveRegistryProfile(draft, password: passwordInput)
            selectedProfileID = saved.id
            draft = saved
            hasStoredPassword = saved.id.flatMap { appState.keychain.registryPassword(for: $0) } != nil
            passwordInput = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteProfile(_ profile: RegistryProfile) async {
        errorMessage = nil
        do {
            try await appState.removeRegistryProfile(profile)
            selectedProfileID = appState.registryProfiles.first?.id
            draft = appState.registryProfiles.first ?? RegistryProfile(displayName: "", host: "")
            passwordInput = ""
            validationReport = nil
            deviceApplyResults = [:]
            deviceValidationResults = [:]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importCertificate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.data]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let managed = try appState.registryCertificateService.importCertificate(
                from: url,
                preferredName: draft.displayName.isEmpty ? draft.host : draft.displayName
            )
            draft.caCertificatePath = managed.url.path
            draft.caCertificateFingerprintSHA256 = managed.info.fingerprintSHA256
            draft.caCertificateFingerprintSHA1 = managed.info.fingerprintSHA1
            draft.caCertificateCommonName = managed.info.commonName ?? managed.info.subjectSummary
            draft.caCertificateIssuer = managed.info.issuerSummary
            draft.caCertificateExpiresAt = managed.info.notValidAfter
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installTrust() async {
        guard let path = draft.caCertificatePath else { return }
        isTrusting = true
        do {
            try appState.registryCertificateService.installTrust(for: URL(fileURLWithPath: path))
        } catch {
            errorMessage = error.localizedDescription
        }
        isTrusting = false
    }

    private func runValidation() async {
        errorMessage = nil
        do {
            let report = try await appState.validateRegistryProfile(draft)
            validationReport = report
            if let refreshed = appState.registryProfiles.first(where: { $0.id == draft.id }) {
                draft = refreshed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyToSelectedDevices() async {
        isApplyingToDevices = true
        errorMessage = nil
        deviceApplyResults = [:]

        for device in selectedDevices {
            guard let id = device.id else { continue }
            do {
                let result = try await appState.applyRegistryProfile(draft, to: id)
                deviceApplyResults[id] = result
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        isApplyingToDevices = false
    }

    private func runDevicePreflight() async {
        isRunningDevicePreflight = true
        errorMessage = nil
        deviceValidationResults = [:]

        for device in selectedDevices {
            guard let id = device.id else { continue }
            do {
                let result = try await appState.validateRegistryProfile(
                    draft,
                    on: id,
                    image: testImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : testImage
                )
                deviceValidationResults[id] = result
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        isRunningDevicePreflight = false
    }

    private func trustStateRow(for path: String) -> some View {
        let state = appState.registryCertificateService.trustState(for: URL(fileURLWithPath: path))
        let label: String
        let color: Color

        switch state {
        case .trusted:
            label = "Trusted on This Mac"
            color = .green
        case .untrusted:
            label = "Not Trusted Yet"
            color = .orange
        case .missing:
            label = "Certificate Missing"
            color = .red
        }

        return Label(label, systemImage: "checkmark.shield")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
    }

    private func infoRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func statusIcon(_ status: RegistryValidationStatus) -> String {
        switch status {
        case .unknown:
            return "questionmark.circle"
        case .pass:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .fail:
            return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: RegistryValidationStatus) -> Color {
        switch status {
        case .unknown:
            return .secondary
        case .pass:
            return .green
        case .warning:
            return .orange
        case .fail:
            return .red
        }
    }
}
