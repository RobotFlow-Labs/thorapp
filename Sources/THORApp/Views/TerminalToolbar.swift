import SwiftUI
import THORShared

/// Toolbar buttons for opening terminals — Codex-style.
struct TerminalToolbar: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @State private var availableTerminals: [TerminalApp] = []
    @State private var selectedTerminal: TerminalApp?

    var body: some View {
        HStack(spacing: 4) {
            // Primary terminal button with dropdown
            Menu {
                ForEach(availableTerminals) { terminal in
                    Button {
                        selectedTerminal = terminal
                        openSSH(with: terminal)
                    } label: {
                        Label(terminal.name, systemImage: "terminal")
                    }
                }
            } label: {
                Label("Terminal", systemImage: "terminal")
                    .labelStyle(.iconOnly)
            } primaryAction: {
                openSSH(with: selectedTerminal)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .help("Open SSH terminal to \(device.displayName)")

            // Quick SSH button
            Button {
                openSSH(with: selectedTerminal)
            } label: {
                Image(systemName: "rectangle.terminal")
            }
            .buttonStyle(.borderless)
            .help("New SSH session")

            // Local terminal at project directory
            Button {
                TerminalLauncher.openLocal(
                    at: "~/",
                    terminalApp: selectedTerminal
                )
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(.borderless)
            .help("Open local terminal")
        }
        .onAppear {
            availableTerminals = TerminalLauncher.availableTerminals
            selectedTerminal = availableTerminals.first
        }
    }

    private func openSSH(with terminal: TerminalApp?) {
        let config = appState.connectionStates[device.id ?? 0]
        let isLocalSim = device.hostname == "localhost" || device.hostname == "127.0.0.1"
        let port = isLocalSim ? 2222 : 22 // TODO: read from DeviceConfig

        TerminalLauncher.openSSH(
            host: device.hostname,
            port: port,
            username: "jetson",
            terminalApp: terminal
        )
    }
}
