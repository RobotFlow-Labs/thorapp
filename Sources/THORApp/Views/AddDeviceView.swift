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

    // Discovery
    @State private var discovery = NetworkDiscovery()
    @State private var showingDiscovery = false

    // SSH Key
    @State private var showingKeyGen = false
    @State private var generatedKeyPath: String?

    // Host Key Verification (TOFU)
    @State private var hostKeyInfo: HostKeyInfo?
    @State private var showingHostKeyConfirm = false
    @State private var isVerifyingHostKey = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // Discovery section
                Section {
                    HStack {
                        Button("Scan Network") {
                            showingDiscovery = true
                            Task { await discovery.scan() }
                        }
                        .disabled(discovery.isScanning)

                        if discovery.isScanning {
                            ProgressView().controlSize(.small)
                        }

                        Spacer()

                        // Quick presets for Docker sims
                        Menu("Quick Add") {
                            Button("Jetson Thor Sim (localhost:2222)") {
                                displayName = "Jetson Thor Sim"
                                hostname = "localhost"
                                port = "2222"
                                authMethod = .password
                                password = "jetson"
                            }
                            Button("Jetson Orin Sim (localhost:2223)") {
                                displayName = "Jetson Orin Sim"
                                hostname = "localhost"
                                port = "2223"
                                authMethod = .password
                                password = "jetson"
                            }
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                    }

                    if showingDiscovery && !discovery.discoveredDevices.isEmpty {
                        ForEach(discovery.discoveredDevices) { device in
                            Button {
                                hostname = device.hostname
                                displayName = device.displayName
                                showingDiscovery = false
                            } label: {
                                HStack {
                                    Image(systemName: "cpu")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading) {
                                        Text(device.displayName)
                                            .font(.system(size: 13))
                                        Text("\(device.hostname) — via \(device.source.rawValue)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else if showingDiscovery && !discovery.isScanning {
                        Text("No Jetson devices found on the network. Use manual entry below.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Discovery")
                }

                Section("Device Info") {
                    TextField("Display Name", text: $displayName)
                    TextField("Hostname or IP", text: $hostname)
                    TextField("SSH Port", text: $port)
                    Picker("Environment", selection: $environment) {
                        ForEach(DeviceEnvironment.allCases, id: \.self) { env in
                            Text(env.rawValue.capitalized).tag(env)
                        }
                    }
                }

                Section("SSH Authentication") {
                    TextField("Username", text: $username)
                    Picker("Auth Method", selection: $authMethod) {
                        Text("SSH Key").tag(AuthMethod.sshKey)
                        Text("Password").tag(AuthMethod.password)
                    }
                    .pickerStyle(.segmented)

                    switch authMethod {
                    case .sshKey:
                        HStack {
                            TextField("Key Path", text: $sshKeyPath)
                            Button("Browse") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
                                if panel.runModal() == .OK, let url = panel.url {
                                    sshKeyPath = url.path
                                }
                            }
                            .controlSize(.small)
                        }
                        Button("Generate New SSH Key") {
                            Task { await generateSSHKey() }
                        }
                        .controlSize(.small)
                        if let keyPath = generatedKeyPath {
                            Text("Key generated: \(keyPath)")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }
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
        .frame(width: 520, height: 560)
        .alert("Verify Host Key", isPresented: $showingHostKeyConfirm) {
            Button("Trust & Continue") {
                // User confirmed — proceed with enrollment
                Task { await addDevice() }
            }
            Button("Cancel", role: .cancel) {
                hostKeyInfo = nil
            }
        } message: {
            if let info = hostKeyInfo {
                Text("First connection to \(hostname).\n\nFingerprint (\(info.keyType)):\n\(info.fingerprint)\n\nDo you trust this host?")
            }
        }
    }

    // MARK: - Actions

    private func addDevice() async {
        isSaving = true
        errorMessage = nil

        // Step 0: Verify host key (TOFU)
        let sshPort = Int(port) ?? 22
        if hostKeyInfo == nil {
            isVerifyingHostKey = true
            let verifier = HostKeyVerifier()
            let result = await verifier.fetchFingerprint(host: hostname, port: sshPort)
            isVerifyingHostKey = false

            switch result {
            case .success(let info):
                hostKeyInfo = info
                showingHostKeyConfirm = true
                isSaving = false
                return  // Wait for user confirmation
            case .unreachable:
                errorMessage = "Cannot reach \(hostname):\(sshPort). Check the hostname and port."
                isSaving = false
                return
            case .error(let msg):
                errorMessage = "Host key scan failed: \(msg)"
                isSaving = false
                return
            }
        }

        let device = Device(
            displayName: displayName,
            hostname: hostname,
            lastKnownIP: hostname,
            environment: environment
        )

        do {
            try await appState.addDevice(device)

            // Store credentials in Keychain and device config
            if let deviceID = appState.devices.last?.id {
                switch authMethod {
                case .sshKey:
                    let expanded = NSString(string: sshKeyPath).expandingTildeInPath
                    try appState.keychain.storeSSHKeyPath(expanded, for: deviceID)
                case .password:
                    try appState.keychain.storePassword(password, for: deviceID)
                }

                // Store host key fingerprint
                if let keyInfo = hostKeyInfo, let db = appState.db {
                    let identity = DeviceIdentity(
                        deviceID: deviceID,
                        hostKeyFingerprint: keyInfo.fingerprint
                    )
                    try await db.writer.write { [identity] dbConn in
                        let record = identity
                        try record.insert(dbConn)
                    }
                }

                // Persist SSH config
                let config = DeviceConfig(
                    deviceID: deviceID,
                    sshUsername: username,
                    sshPort: sshPort,
                    agentPort: sshPort == 2222 ? 8470 : (sshPort == 2223 ? 8471 : 8470),
                    autoConnect: true,
                    autoReconnect: true
                )
                try await appState.connector?.saveDeviceConfig(config)
            }

            // Auto-connect: try direct agent connection for Docker sims
            if let saved = appState.devices.last {
                let sshPort = Int(port) ?? 22
                if hostname == "localhost" || hostname == "127.0.0.1" {
                    let agentPort = sshPort == 2222 ? 8470 : (sshPort == 2223 ? 8471 : 8470)
                    try await appState.connectDevice(saved, directPort: agentPort)
                }
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func generateSSHKey() async {
        let keyPath = NSHomeDirectory() + "/.ssh/thor_jetson_\(UUID().uuidString.prefix(8))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-t", "ed25519", "-f", keyPath, "-N", "", "-C", "thor@\(hostname)"]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                sshKeyPath = keyPath
                generatedKeyPath = keyPath

                // Copy public key to pasteboard for easy setup
                let pubKey = try String(contentsOfFile: keyPath + ".pub", encoding: .utf8)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pubKey, forType: .string)
            }
        } catch {
            errorMessage = "Key generation failed: \(error.localizedDescription)"
        }
    }
}

private enum AuthMethod: String, CaseIterable {
    case sshKey
    case password
}
