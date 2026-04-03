import AppKit
import SwiftUI
import THORShared

struct RegistryWorkspaceView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedProfileID: Int64?
    @State private var draft = RegistryProfile(displayName: "", host: "")
    @State private var passwordInput = ""
    @State private var validationReport: RegistryValidationReport?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isTrusting = false
    @State private var hasStoredPassword = false

    private var selectedProfile: RegistryProfile? {
        appState.registryProfiles.first(where: { $0.id == selectedProfileID })
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
                    errorMessage = nil
                    hasStoredPassword = false
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
                profileForm
                certificateSection
                validationSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.id == nil ? "New Registry Profile" : draft.displayName)
                    .font(.system(size: 20, weight: .semibold))
                Text(draft.endpointLabel)
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
        GroupBox("Validation") {
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
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: statusIcon(stage.status))
                                .foregroundStyle(statusColor(stage.status))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.name)
                                    .font(.system(size: 12, weight: .medium))
                                Text(stage.message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if let profile = selectedProfile, let message = profile.lastValidationMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run validation to check trust, reachability, and authentication readiness.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadDraftFromSelection() {
        guard let selectedProfile else {
            hasStoredPassword = false
            return
        }
        draft = selectedProfile
        passwordInput = ""
        validationReport = nil
        hasStoredPassword = selectedProfile.id.flatMap { appState.keychain.registryPassword(for: $0) } != nil
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
