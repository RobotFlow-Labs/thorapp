import SwiftUI
import THORShared

struct AddDeviceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var onboardingMode = DeviceOnboardingMode.brandNew
    @State private var firstNetworkPath = FirstNetworkPath.ethernet
    @State private var hostSnapshot = JetsonThorHostSnapshot.empty

    @State private var displayName = ""
    @State private var hostname = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var environment = DeviceEnvironment.lab
    @State private var authMethod = AuthMethod.sshKey
    @State private var sshKeyPath = "~/.ssh/id_ed25519"
    @State private var password = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var discovery = NetworkDiscovery()
    @State private var showingDiscovery = false

    @State private var generatedKeyPath: String?

    @State private var hostKeyInfo: HostKeyInfo?
    @State private var showingHostKeyConfirm = false
    @State private var isVerifyingHostKey = false
    @State private var showingThorQuickStart = false

    private let quickStartSupport = JetsonThorQuickStartSupport()

    private var trimmedDisplayName: String {
        displayName.trimmed
    }

    private var trimmedHostname: String {
        hostname.trimmed
    }

    private var trimmedUsername: String {
        username.trimmed
    }

    private var trimmedPassword: String {
        password.trimmed
    }

    private var canEnroll: Bool {
        !trimmedDisplayName.isEmpty &&
        !trimmedHostname.isEmpty &&
        !trimmedUsername.isEmpty &&
        !isSaving &&
        (authMethod != .password || !trimmedPassword.isEmpty)
    }

    private var recommendedDebugSerial: JetsonThorSerialCandidate? {
        hostSnapshot.debugSerialCandidates.first(where: \.recommended) ?? hostSnapshot.debugSerialCandidates.first
    }

    private var recommendedOEMConfigSerial: JetsonThorSerialCandidate? {
        hostSnapshot.oemConfigCandidates.first(where: \.recommended) ?? hostSnapshot.oemConfigCandidates.first
    }

    private var recommendedPublicKey: JetsonThorPublicKeyCandidate? {
        hostSnapshot.publicKeyCandidates.first(where: \.recommended) ?? hostSnapshot.publicKeyCandidates.first
    }

    private var suggestedHostText: String {
        switch firstNetworkPath {
        case .usbTether:
            return "192.168.55.1"
        case .ethernet:
            return ""
        }
    }

    private var networkHandoffCopy: String {
        switch firstNetworkPath {
        case .usbTether:
            return "Use USB console for first boot, then enroll over the known `192.168.55.1` tether address."
        case .ethernet:
            return "Use USB console for first boot, keep Ethernet connected, then enroll once the board has a wired hostname or DHCP address."
        }
    }

    private var hostnamePrompt: String {
        switch onboardingMode {
        case .brandNew:
            switch firstNetworkPath {
            case .usbTether:
                return "Use `192.168.55.1` after first boot"
            case .ethernet:
                return "Enter Ethernet hostname or DHCP IP once it comes up"
            }
        case .reachable:
            return "Hostname or IP"
        }
    }

    private var discoveryHelperCopy: String {
        switch onboardingMode {
        case .brandNew:
            switch firstNetworkPath {
            case .usbTether:
                return "If you stay on USB tether, you usually do not need discovery. THOR can prefill `192.168.55.1` for you."
            case .ethernet:
                return "Use discovery after OEM-config and boot are done and the board is visible on the wired network."
            }
        case .reachable:
            return "Scan the local network for SSH-visible Jetson devices, or enter the host details manually."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                pathSection

                if onboardingMode == .brandNew {
                    firstBootPlanSection
                }

                discoverySection
                deviceInfoSection
                authenticationSection

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

                Button(onboardingMode == .brandNew ? "Enroll Device" : "Add Device") {
                    Task { await addDevice() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canEnroll)
            }
            .padding(20)
        }
        .frame(width: 700, height: 760)
        .task {
            await refreshFirstBootSnapshot()
        }
        .onChange(of: firstNetworkPath) { _, _ in
            if onboardingMode == .brandNew {
                applySuggestedConnectionDefaults()
            }
        }
        .alert("Verify Host Key", isPresented: $showingHostKeyConfirm) {
            Button("Trust & Continue") {
                Task { await addDevice() }
            }
            Button("Cancel", role: .cancel) {
                hostKeyInfo = nil
            }
        } message: {
            if let info = hostKeyInfo {
                Text("First connection to \(trimmedHostname).\n\nFingerprint (\(info.keyType)):\n\(info.fingerprint)\n\nDo you trust this host?")
            }
        }
        .sheet(isPresented: $showingThorQuickStart) {
            ScrollView {
                JetsonThorQuickStartView(device: nil, showsBackButton: true)
                    .padding(24)
                    .frame(minWidth: 760)
            }
            .frame(width: 820, height: 760)
        }
    }

    private var pathSection: some View {
        Section("Starting Point") {
            Picker("Onboarding Path", selection: $onboardingMode) {
                ForEach(DeviceOnboardingMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(onboardingMode.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var firstBootPlanSection: some View {
        Section("New Device Bring-Up") {
            VStack(alignment: .leading, spacing: 12) {
                firstBootStep(
                    number: 1,
                    title: "USB console first",
                    detail: "Connect Debug-USB for UEFI / BSP install, then move to the OEM-config console when the board asks for first-boot setup."
                )

                firstBootStep(
                    number: 2,
                    title: "Record the real username",
                    detail: "The username you create during OEM-config is the SSH username THOR must store. THOR should not guess it."
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("3")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose the first network handoff")
                                .font(.system(size: 13, weight: .semibold))
                            Text(networkHandoffCopy)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("First Reachable Path", selection: $firstNetworkPath) {
                        ForEach(FirstNetworkPath.allCases, id: \.self) { path in
                            Text(path.title).tag(path)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Button("Open First-Boot Guide") {
                        showingThorQuickStart = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh Host Detection") {
                        Task { await refreshFirstBootSnapshot() }
                    }
                    .buttonStyle(.bordered)

                    Button(firstNetworkPath == .usbTether ? "Use USB Tether Defaults" : "Prepare for Ethernet Enrollment") {
                        applySuggestedConnectionDefaults()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                VStack(spacing: 0) {
                    firstBootStatusRow(
                        title: "Debug-USB Console",
                        value: recommendedDebugSerial?.path ?? "No `/dev/cu.usbserial-*` device detected",
                        detail: recommendedDebugSerial == nil
                            ? "Connect the Mac to the Thor Debug-USB port before bring-up."
                            : "THOR can see the recommended UEFI console path now."
                    )

                    Divider()

                    firstBootStatusRow(
                        title: "OEM-config Console",
                        value: recommendedOEMConfigSerial?.path ?? "No `/dev/cu.usbmodem*` device detected",
                        detail: recommendedOEMConfigSerial == nil
                            ? "After the installer boots NVMe, move the cable to the OEM-config data port."
                            : "THOR can see the text-mode first-boot console path."
                    )

                    Divider()

                    firstBootStatusRow(
                        title: "USB Tether",
                        value: hostSnapshot.usbTetherDetected ? hostSnapshot.usbTetherHostAddresses.joined(separator: ", ") : "No `192.168.55.x` address detected yet",
                        detail: hostSnapshot.usbTetherDetected
                            ? "The Mac already sees the USB network gadget."
                            : "This is optional if you plan to enroll over Ethernet instead."
                    )

                    Divider()

                    firstBootStatusRow(
                        title: "SSH Key",
                        value: recommendedPublicKey?.path ?? "No public key found",
                        detail: recommendedPublicKey == nil
                            ? "Generate a key below or import one before bootstrap."
                            : "THOR will use the recommended public key for bootstrap and SSH access."
                    )
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.vertical, 4)
        }
    }

    private var discoverySection: some View {
        Section(onboardingMode == .brandNew ? "Reachable Device Discovery" : "Discovery") {
            VStack(alignment: .leading, spacing: 10) {
                Text(discoveryHelperCopy)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

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

                    Menu("Quick Add") {
                        Button("Jetson Thor Sim (localhost:2222)") {
                            onboardingMode = .reachable
                            displayName = "Jetson Thor Sim"
                            hostname = "localhost"
                            username = "jetson"
                            port = "2222"
                            authMethod = .password
                            password = "jetson"
                        }
                        Button("Jetson Orin Sim (localhost:2223)") {
                            onboardingMode = .reachable
                            displayName = "Jetson Orin Sim"
                            hostname = "localhost"
                            username = "jetson"
                            port = "2223"
                            authMethod = .password
                            password = "jetson"
                        }
                        Button("USB Tether (192.168.55.1)") {
                            onboardingMode = .brandNew
                            firstNetworkPath = .usbTether
                            applySuggestedConnectionDefaults()
                        }
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                }

                if showingDiscovery && !discovery.discoveredDevices.isEmpty {
                    ForEach(discovery.discoveredDevices) { device in
                        Button {
                            onboardingMode = .reachable
                            hostname = device.hostname
                            if trimmedDisplayName.isEmpty {
                                displayName = device.displayName
                            }
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
                    Text("No Jetson devices found on the network. Enter the address manually below.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var deviceInfoSection: some View {
        Section("Device Info") {
            TextField("Display Name", text: $displayName)

            TextField(hostnamePrompt, text: $hostname)

            TextField("SSH Port", text: $port)

            Picker("Environment", selection: $environment) {
                ForEach(DeviceEnvironment.allCases, id: \.self) { env in
                    Text(env.rawValue.capitalized).tag(env)
                }
            }

            if onboardingMode == .brandNew && firstNetworkPath == .ethernet {
                Text("Recommended: finish first boot over USB console, wait for the wired hostname or DHCP IP, then enter that Ethernet address here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var authenticationSection: some View {
        Section("SSH Authentication") {
            TextField("Username created during OEM-config", text: $username)

            if onboardingMode == .brandNew {
                Text("Do not assume `jetson` or `nvidia`. Use the exact username you created on the device.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

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
                } else if let recommendedPublicKey {
                    Text("Recommended key detected: \(recommendedPublicKey.path)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            case .password:
                SecureField("Password", text: $password)
            }
        }
    }

    private func firstBootStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func firstBootStatusRow(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
        }
    }

    private func applySuggestedConnectionDefaults() {
        if trimmedDisplayName.isEmpty {
            displayName = "Jetson AGX Thor"
        }

        switch firstNetworkPath {
        case .usbTether:
            hostname = "192.168.55.1"
            port = "22"
        case .ethernet:
            if trimmedHostname == "192.168.55.1" {
                hostname = ""
            }
            port = "22"
        }
    }

    private func refreshFirstBootSnapshot() async {
        hostSnapshot = quickStartSupport.snapshot()

        if generatedKeyPath == nil,
           sshKeyPath == "~/.ssh/id_ed25519",
           let recommendedPublicKey {
            let privateKeyPath = recommendedPublicKey.path.replacingOccurrences(of: ".pub", with: "")
            if FileManager.default.fileExists(atPath: privateKeyPath) {
                sshKeyPath = privateKeyPath
            }
        }
    }

    private func addDevice() async {
        isSaving = true
        errorMessage = nil

        guard !trimmedDisplayName.isEmpty else {
            errorMessage = "Device name is required."
            isSaving = false
            return
        }

        guard !trimmedHostname.isEmpty else {
            errorMessage = "Hostname or IP is required."
            isSaving = false
            return
        }

        guard !trimmedUsername.isEmpty else {
            errorMessage = "Use the SSH username that exists on the device."
            isSaving = false
            return
        }

        if authMethod == .password && trimmedPassword.isEmpty {
            errorMessage = "Password is required when password auth is selected."
            isSaving = false
            return
        }

        let sshPort = Int(port) ?? 22
        if hostKeyInfo == nil {
            isVerifyingHostKey = true
            let verifier = HostKeyVerifier()
            let result = await verifier.fetchFingerprint(host: trimmedHostname, port: sshPort)
            isVerifyingHostKey = false

            switch result {
            case .success(let info):
                hostKeyInfo = info
                showingHostKeyConfirm = true
                isSaving = false
                return
            case .unreachable:
                errorMessage = "Cannot reach \(trimmedHostname):\(sshPort). Finish first boot and confirm the network path before enrolling."
                isSaving = false
                return
            case .error(let msg):
                errorMessage = "Host key scan failed: \(msg)"
                isSaving = false
                return
            }
        }

        let device = Device(
            displayName: trimmedDisplayName,
            hostname: trimmedHostname,
            lastKnownIP: trimmedHostname,
            environment: environment
        )

        do {
            try await appState.addDevice(device)

            if let deviceID = appState.devices.last?.id {
                switch authMethod {
                case .sshKey:
                    let expanded = NSString(string: sshKeyPath).expandingTildeInPath
                    try appState.keychain.storeSSHKeyPath(expanded, for: deviceID)
                case .password:
                    try appState.keychain.storePassword(trimmedPassword, for: deviceID)
                }

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

                let config = DeviceConfig(
                    deviceID: deviceID,
                    sshUsername: trimmedUsername,
                    sshPort: sshPort,
                    agentPort: sshPort == 2222 ? 8470 : (sshPort == 2223 ? 8471 : 8470),
                    autoConnect: true,
                    autoReconnect: true
                )
                try await appState.connector?.saveDeviceConfig(config)
            }

            if let saved = appState.devices.last,
               trimmedHostname == "localhost" || trimmedHostname == "127.0.0.1" {
                let agentPort = sshPort == 2222 ? 8470 : (sshPort == 2223 ? 8471 : 8470)
                try await appState.connectDevice(saved, directPort: agentPort)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func generateSSHKey() async {
        let targetHost = trimmedHostname.isEmpty ? "jetson" : trimmedHostname
        let keyPath = NSHomeDirectory() + "/.ssh/thor_jetson_\(UUID().uuidString.prefix(8))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-t", "ed25519", "-f", keyPath, "-N", "", "-C", "thor@\(targetHost)"]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                sshKeyPath = keyPath
                generatedKeyPath = keyPath

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

private enum DeviceOnboardingMode: CaseIterable {
    case brandNew
    case reachable

    var title: String {
        switch self {
        case .brandNew:
            return "Brand-New Device"
        case .reachable:
            return "Already Reachable"
        }
    }

    var detail: String {
        switch self {
        case .brandNew:
            return "Use this path when the board still needs first boot, OEM-config, or an initial network handoff before THOR can enroll it."
        case .reachable:
            return "Use this path when you already know the hostname or IP and just want to enroll the device into THOR."
        }
    }
}

private enum FirstNetworkPath: CaseIterable {
    case ethernet
    case usbTether

    var title: String {
        switch self {
        case .ethernet:
            return "Ethernet Later"
        case .usbTether:
            return "USB Tether"
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
