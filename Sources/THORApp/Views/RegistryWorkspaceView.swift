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

    private var trimmedDisplayName: String {
        draft.displayName.trimmed
    }

    private var trimmedHost: String {
        draft.host.trimmed
    }

    private var trimmedUsername: String {
        (draft.username ?? "").trimmed
    }

    private var trimmedNamespace: String {
        draft.repositoryNamespace.trimmed
    }

    private var trimmedTestImage: String {
        testImage.trimmed
    }

    private var hasPasswordAvailable: Bool {
        hasStoredPassword || !passwordInput.trimmed.isEmpty
    }

    private var macTrustStatus: RegistryValidationStatus {
        guard draft.scheme == .https else { return .pass }
        guard let path = draft.caCertificatePath else { return .pass }
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
        guard !trimmedUsername.isEmpty else { return .pass }
        return hasPasswordAvailable ? .pass : .warning
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

    private var connectionSnapshot: RegistryWorkspaceSnapshot {
        if draft.id == nil {
            return .init(
                title: "Connection",
                detail: "Save this profile once the name and host look right.",
                status: .warning
            )
        }

        if trimmedUsername.isEmpty {
            return .init(
                title: "Connection",
                detail: "Saved for public or anonymous registry access.",
                status: .pass
            )
        }

        if hasPasswordAvailable {
            return .init(
                title: "Connection",
                detail: "Saved with credentials ready for validation and rollout.",
                status: .pass
            )
        }

        return .init(
            title: "Connection",
            detail: "Username is set, but a password still needs to be stored.",
            status: .warning
        )
    }

    private var trustSnapshot: RegistryWorkspaceSnapshot {
        guard draft.scheme == .https else {
            return .init(
                title: "TLS Trust",
                detail: "This profile uses HTTP, so no certificate trust is involved.",
                status: .pass
            )
        }

        guard let path = draft.caCertificatePath else {
            return .init(
                title: "TLS Trust",
                detail: "Using standard macOS trust. Import a custom CA only for private registries.",
                status: .pass
            )
        }

        switch appState.registryCertificateService.trustState(for: URL(fileURLWithPath: path)) {
        case .trusted:
            return .init(
                title: "TLS Trust",
                detail: "Custom CA is attached and trusted on this Mac.",
                status: .pass
            )
        case .untrusted(let reason):
            return .init(
                title: "TLS Trust",
                detail: reason ?? "Custom CA is attached but not trusted on this Mac yet.",
                status: .warning
            )
        case .missing:
            return .init(
                title: "TLS Trust",
                detail: "The attached certificate file is missing from managed storage.",
                status: .fail
            )
        }
    }

    private var macValidationSnapshot: RegistryWorkspaceSnapshot {
        let detail: String
        if let report = validationReport {
            detail = report.summary
        } else if let message = selectedProfile?.lastValidationMessage, !message.isEmpty {
            detail = message
        } else {
            detail = "Run a Mac-side check to verify address, trust, and authentication."
        }

        return .init(
            title: "Check on This Mac",
            detail: detail,
            status: lastMacValidationStatus
        )
    }

    private var jetsonRolloutSnapshot: RegistryWorkspaceSnapshot {
        if connectedDeviceIDs.isEmpty {
            return .init(
                title: "Jetsons",
                detail: "No connected Jetsons right now. Rollout can wait until a device is online.",
                status: .unknown
            )
        }

        if selectedDeviceIDs.isEmpty {
            return .init(
                title: "Jetsons",
                detail: "Choose one or more connected Jetsons for rollout and preflight.",
                status: .unknown
            )
        }

        if let failingMessage = firstJetsonIssueMessage {
            return .init(
                title: "Jetsons",
                detail: failingMessage,
                status: deviceRolloutStatus
            )
        }

        if !deviceValidationResults.isEmpty {
            return .init(
                title: "Jetsons",
                detail: "Latest preflight covered \(deviceValidationResults.count) device\(deviceValidationResults.count == 1 ? "" : "s").",
                status: deviceRolloutStatus
            )
        }

        if !deviceApplyResults.isEmpty {
            return .init(
                title: "Jetsons",
                detail: "Profile applied to \(deviceApplyResults.count) device\(deviceApplyResults.count == 1 ? "" : "s").",
                status: deviceRolloutStatus
            )
        }

        return .init(
            title: "Jetsons",
            detail: "Apply the profile to the selected Jetsons, then run a device-side preflight.",
            status: .unknown
        )
    }

    private var nextActionSnapshot: RegistryWorkspaceSnapshot {
        if trimmedDisplayName.isEmpty || trimmedHost.isEmpty {
            return .init(
                title: "Finish the basic fields",
                detail: "Add a profile name and registry host so THOR knows where to connect.",
                status: .warning
            )
        }

        if draft.id == nil {
            return .init(
                title: "Save this profile",
                detail: "Saving turns the current draft into a reusable registry profile across THOR workflows.",
                status: .warning
            )
        }

        if !trimmedUsername.isEmpty && !hasPasswordAvailable {
            return .init(
                title: "Store the password",
                detail: "This registry needs authentication, so THOR needs a password in Keychain before it can validate or roll out the profile.",
                status: .warning
            )
        }

        if draft.scheme == .https, draft.caCertificatePath != nil, macTrustStatus != .pass {
            return .init(
                title: "Trust the imported CA",
                detail: "The custom certificate is attached, but macOS still needs to trust it before local checks will pass cleanly.",
                status: macTrustStatus
            )
        }

        if lastMacValidationStatus == .unknown {
            return .init(
                title: "Check the registry on this Mac",
                detail: "Run the Mac-side check once to verify reachability, TLS trust, and credentials.",
                status: .warning
            )
        }

        if lastMacValidationStatus == .warning || lastMacValidationStatus == .fail {
            return .init(
                title: "Fix the Mac-side check",
                detail: macValidationSnapshot.detail,
                status: lastMacValidationStatus
            )
        }

        if connectedDeviceIDs.isEmpty {
            return .init(
                title: "Local setup is ready",
                detail: "The profile looks good on this Mac. Connect a Jetson whenever you want to roll it out.",
                status: .pass
            )
        }

        if selectedDeviceIDs.isEmpty {
            return .init(
                title: "Choose Jetsons for rollout",
                detail: "Select one or more connected devices before applying the profile.",
                status: .warning
            )
        }

        if deviceRolloutStatus == .unknown {
            return .init(
                title: "Apply and preflight on Jetsons",
                detail: "Push the profile to the selected devices, then optionally pull a test image to confirm end-to-end access.",
                status: .warning
            )
        }

        if deviceRolloutStatus == .warning || deviceRolloutStatus == .fail {
            return .init(
                title: "Resolve Jetson rollout issues",
                detail: jetsonRolloutSnapshot.detail,
                status: deviceRolloutStatus
            )
        }

        return .init(
            title: "Ready to use",
            detail: "This profile is in good shape for pull and deploy workflows on both your Mac and the selected Jetsons.",
            status: .pass
        )
    }

    private var firstJetsonIssueMessage: String? {
        for result in deviceValidationResults.values {
            if let stage = result.stages.first(where: { $0.status == .fail || $0.status == .warning }) {
                return stage.message
            }
        }

        for result in deviceApplyResults.values where !result.message.isEmpty {
            return result.message
        }

        return nil
    }

    private var headerTitle: String {
        draft.id == nil ? "New Registry Profile" : draft.displayName
    }

    private var headerDescription: String {
        if draft.id == nil {
            return "Describe how THOR should reach this registry, then verify it locally before rolling it out to Jetsons."
        }
        return "This saved profile powers image pull and deploy workflows without making you rebuild the setup every time."
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Registry Profiles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Saved endpoints for pull and deploy workflows.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
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
                    RegistrySidebarRow(profile: profile)
                        .tag(profile.id)
                }
            }
            .listStyle(.sidebar)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let errorMessage {
                    errorBanner(message: errorMessage)
                }
                readinessSection
                connectionSection
                certificateSection
                validationSection
                deviceRolloutSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 20, weight: .semibold))

                Text(draft.endpointLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(headerDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    RegistryInfoPill(title: draft.scheme.rawValue.uppercased(), color: .blue)
                    RegistryInfoPill(
                        title: trimmedUsername.isEmpty ? "No Auth" : (hasPasswordAvailable ? "Auth Ready" : "Password Missing"),
                        color: trimmedUsername.isEmpty ? .secondary : (hasPasswordAvailable ? .green : .orange)
                    )
                    RegistryInfoPill(
                        title: trimmedNamespace.isEmpty ? "Repository Root" : "Namespace: \(trimmedNamespace)",
                        color: .secondary
                    )
                }
            }

            Spacer()

            HStack(spacing: 8) {
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

                Button(isSaving ? "Saving..." : "Save") {
                    Task { await saveProfile() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || trimmedDisplayName.isEmpty || trimmedHost.isEmpty)
            }
        }
    }

    private var readinessSection: some View {
        GroupBox("Readiness") {
            VStack(alignment: .leading, spacing: 12) {
                RegistryNextActionCard(snapshot: nextActionSnapshot)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    RegistryReadinessCard(snapshot: connectionSnapshot)
                    RegistryReadinessCard(snapshot: trustSnapshot)
                    RegistryReadinessCard(snapshot: macValidationSnapshot)
                    RegistryReadinessCard(snapshot: jetsonRolloutSnapshot)
                }
            }
        }
    }

    private var connectionSection: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 12) {
                sectionIntro("Start with the address THOR should use. Add credentials only if the registry actually asks for them.")

                TextField("Profile Name", text: $draft.displayName)

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

                TextField("Repository Namespace (optional)", text: $draft.repositoryNamespace)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Authentication")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Leave credentials empty for public registries. THOR stores passwords in Keychain, not in the profile itself.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField(
                            "Username (optional)",
                            text: Binding(
                                get: { draft.username ?? "" },
                                set: { draft.username = $0.trimmed.isEmpty ? nil : $0 }
                            )
                        )

                        SecureField(
                            hasStoredPassword && passwordInput.isEmpty ? "Password saved in Keychain" : "Password",
                            text: $passwordInput
                        )
                    }
                }
            }
        }
    }

    private var certificateSection: some View {
        GroupBox("TLS Trust") {
            VStack(alignment: .leading, spacing: 10) {
                if draft.scheme == .http {
                    sectionIntro("This profile uses HTTP, so THOR will skip certificate trust management.")
                } else {
                    sectionIntro("Most registries work with standard system trust. Import a custom CA only for private or lab registries.")

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
                        Text("No custom CA attached. THOR will rely on macOS system trust for HTTPS connections.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(draft.caCertificatePath == nil ? "Import Custom CA" : "Replace Custom CA") {
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
    }

    private var validationSection: some View {
        GroupBox("Check on This Mac") {
            VStack(alignment: .leading, spacing: 10) {
                sectionIntro("Use this check before a demo or rollout to confirm the registry address, trust, and credentials from your Mac.")

                HStack {
                    RegistryInfoPill(
                        title: lastMacValidationStatus == .unknown ? "Not Checked Yet" : lastMacValidationStatus.displayTitle,
                        color: lastMacValidationStatus.tint
                    )

                    if let validatedAt = selectedProfile?.lastValidatedAt {
                        Text(validatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Check Registry") {
                        Task { await runValidation() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.id == nil)
                }

                if draft.id == nil {
                    Text("Save the profile first so THOR can keep the result with this registry.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if let report = validationReport {
                    ForEach(report.stages) { stage in
                        validationStageRow(name: stage.name, status: stage.status, message: stage.message)
                    }
                } else if let profile = selectedProfile, let message = profile.lastValidationMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No Mac-side check has been run yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var deviceRolloutSection: some View {
        GroupBox("Apply to Jetsons") {
            VStack(alignment: .leading, spacing: 12) {
                sectionIntro("Push trust and auth settings to connected Jetsons, then optionally pull a test image to confirm device-side access.")

                if appState.devices.isEmpty {
                    Text("No devices are enrolled in THOR yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.devices, id: \.id) { device in
                            if let id = device.id {
                                Toggle(
                                    isOn: Binding(
                                        get: { selectedDeviceIDs.contains(id) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedDeviceIDs.insert(id)
                                            } else {
                                                selectedDeviceIDs.remove(id)
                                            }
                                        }
                                    )
                                ) {
                                    RegistryDeviceRow(
                                        device: device,
                                        connectionStatus: appState.connectionStatus(for: id),
                                        applyResult: deviceApplyResults[id],
                                        validationResult: deviceValidationResults[id]
                                    )
                                }
                                .toggleStyle(.checkbox)
                                .disabled(appState.connectionStatus(for: id) != .connected)
                            }
                        }
                    }
                }

                HStack {
                    TextField("Optional image to pull during preflight", text: $testImage)
                    Button(isApplyingToDevices ? "Applying..." : "Apply Profile") {
                        Task { await applyToSelectedDevices() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.id == nil || selectedDeviceIDs.isEmpty || isApplyingToDevices)

                    Button(isRunningDevicePreflight ? "Checking..." : "Run Preflight") {
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

    private func sectionIntro(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func validationStageRow(name: String, status: RegistryValidationStatus, message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.iconName)
                .foregroundStyle(status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadDraftFromSelection() {
        guard let selectedProfile else {
            draft = RegistryProfile(displayName: "", host: "")
            hasStoredPassword = false
            passwordInput = ""
            validationReport = nil
            selectedDeviceIDs = connectedDeviceIDs
            deviceApplyResults = [:]
            deviceValidationResults = [:]
            errorMessage = nil
            return
        }

        draft = selectedProfile
        passwordInput = ""
        validationReport = nil
        deviceApplyResults = [:]
        deviceValidationResults = [:]
        errorMessage = nil
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
            if let first = appState.registryProfiles.first {
                draft = first
                hasStoredPassword = first.id.flatMap { appState.keychain.registryPassword(for: $0) } != nil
            } else {
                draft = RegistryProfile(displayName: "", host: "")
                hasStoredPassword = false
            }
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
                    image: trimmedTestImage.isEmpty ? nil : trimmedTestImage
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
            label = "Custom CA Trusted on This Mac"
            color = .green
        case .untrusted:
            label = "Custom CA Not Trusted Yet"
            color = .orange
        case .missing:
            label = "Custom CA File Missing"
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
}

private struct RegistryWorkspaceSnapshot {
    let title: String
    let detail: String
    let status: RegistryValidationStatus
}

private struct RegistryReadinessCard: View {
    let snapshot: RegistryWorkspaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: snapshot.status.iconName)
                    .foregroundStyle(snapshot.status.tint)
                Text(snapshot.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                RegistryInfoPill(title: snapshot.status.displayTitle, color: snapshot.status.tint)
            }

            Text(snapshot.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct RegistryNextActionCard: View {
    let snapshot: RegistryWorkspaceSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: snapshot.status.iconName)
                .foregroundStyle(snapshot.status.tint)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(snapshot.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            RegistryInfoPill(title: snapshot.status.displayTitle, color: snapshot.status.tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(snapshot.status.tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct RegistrySidebarRow: View {
    let profile: RegistryProfile

    private var statusTitle: String {
        profile.lastValidationStatus == .unknown ? "Not Checked" : profile.lastValidationStatus.displayTitle
    }

    private var authLabel: String {
        (profile.username ?? "").trimmed.isEmpty ? "No Auth" : "Auth"
    }

    private var namespaceLabel: String {
        profile.repositoryNamespace.trimmed.isEmpty ? "Repository Root" : "Namespace"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(profile.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                RegistryInfoPill(title: statusTitle, color: profile.lastValidationStatus.tint)
            }

            Text(profile.endpointLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                RegistryInfoPill(title: profile.scheme.rawValue.uppercased(), color: .blue)
                RegistryInfoPill(title: authLabel, color: .secondary)
                RegistryInfoPill(title: namespaceLabel, color: .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RegistryDeviceRow: View {
    let device: Device
    let connectionStatus: ConnectionStatus
    let applyResult: DeviceRegistryApplyResponse?
    let validationResult: DeviceRegistryValidationResponse?

    private var deviceMessage: String? {
        if let applyResult, !applyResult.message.isEmpty {
            return applyResult.message
        }

        if let validationResult,
           let stage = validationResult.stages.first(where: { $0.status == .fail || $0.status == .warning }) ?? validationResult.stages.first {
            return stage.message
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(device.displayName)
                    .font(.system(size: 13, weight: .medium))
                RegistryInfoPill(
                    title: connectionStatus.rawValue.capitalized,
                    color: connectionStatus == .connected ? .green : .secondary
                )

                if let validationResult {
                    RegistryInfoPill(title: validationResult.status.displayTitle, color: validationResult.status.tint)
                } else if let applyResult {
                    RegistryInfoPill(title: applyResult.ready ? "Applied" : "Follow-up", color: applyResult.ready ? .green : .orange)
                }
            }

            Text(device.hostname)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let deviceMessage {
                Text(deviceMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RegistryInfoPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private extension RegistryValidationStatus {
    var iconName: String {
        switch self {
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

    var tint: Color {
        switch self {
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

    var displayTitle: String {
        switch self {
        case .unknown:
            return "Pending"
        case .pass:
            return "Ready"
        case .warning:
            return "Attention"
        case .fail:
            return "Failed"
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
