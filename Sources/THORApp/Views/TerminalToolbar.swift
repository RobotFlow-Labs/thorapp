import SwiftUI
import THORShared

/// Toolbar buttons for opening terminals — clean Codex-style with proper icons.
struct TerminalToolbar: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var availableTerminals: [TerminalApp] = []
    @State private var selectedTerminal: TerminalApp?

    var body: some View {
        HStack(spacing: 8) {
            // SSH terminal with app picker dropdown
            Menu {
                Section("Open SSH in...") {
                    ForEach(availableTerminals) { terminal in
                        Button {
                            selectedTerminal = terminal
                            openSSH(with: terminal)
                        } label: {
                            Text(terminal.name)
                        }
                    }
                }
                Divider()
                Button("Copy SSH Command") {
                    let port = sshPort
                    let cmd = "ssh -p \(port) jetson@\(device.hostname)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                }
            } label: {
                Image(systemName: "apple.terminal.fill")
                    .font(.system(size: 14))
            } primaryAction: {
                openSSH(with: selectedTerminal)
            }
            .menuStyle(.borderlessButton)
            .help("SSH Terminal")
        }
        .onAppear {
            availableTerminals = TerminalLauncher.availableTerminals
            selectedTerminal = availableTerminals.first
        }
    }

    private var sshPort: Int {
        let isLocalSim = device.hostname == "localhost" || device.hostname == "127.0.0.1"
        return isLocalSim ? 2222 : 22
    }

    private func openSSH(with terminal: TerminalApp?) {
        TerminalLauncher.openSSH(
            host: device.hostname,
            port: sshPort,
            username: "jetson",
            terminalApp: terminal
        )
    }
}
