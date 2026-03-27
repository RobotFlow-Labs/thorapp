import SwiftUI
import THORShared

struct AddDeviceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var hostname = ""
    @State private var username = "jetson"
    @State private var port = "22"
    @State private var environment = DeviceEnvironment.lab
    @State private var authMethod = AuthMethod.sshKey
    @State private var sshKeyPath = "~/.ssh/id_rsa"
    @State private var password = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Device Info") {
                    TextField("Display Name", text: $displayName)
                    TextField("Hostname or IP", text: $hostname)
                    Picker("Environment", selection: $environment) {
                        ForEach(DeviceEnvironment.allCases, id: \.self) { env in
                            Text(env.rawValue.capitalized).tag(env)
                        }
                    }
                }

                Section("SSH Connection") {
                    TextField("Username", text: $username)
                    TextField("Port", text: $port)
                    Picker("Auth Method", selection: $authMethod) {
                        Text("SSH Key").tag(AuthMethod.sshKey)
                        Text("Password").tag(AuthMethod.password)
                    }
                    .pickerStyle(.segmented)

                    switch authMethod {
                    case .sshKey:
                        TextField("Key Path", text: $sshKeyPath)
                    case .password:
                        SecureField("Password", text: $password)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.system(size: 13))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Device") {
                    Task { await addDevice() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.isEmpty || hostname.isEmpty || isSaving)
            }
            .padding(20)
        }
        .frame(width: 480, height: 420)
    }

    private func addDevice() async {
        isSaving = true
        errorMessage = nil

        let device = Device(
            displayName: displayName,
            hostname: hostname,
            lastKnownIP: hostname,
            environment: environment
        )

        do {
            try await appState.addDevice(device)

            // Store credentials in Keychain
            if let deviceID = appState.devices.last?.id {
                switch authMethod {
                case .sshKey:
                    let expanded = NSString(string: sshKeyPath).expandingTildeInPath
                    try appState.keychain.storeSSHKeyPath(expanded, for: deviceID)
                case .password:
                    try appState.keychain.storePassword(password, for: deviceID)
                }
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

private enum AuthMethod: String, CaseIterable {
    case sshKey
    case password
}
