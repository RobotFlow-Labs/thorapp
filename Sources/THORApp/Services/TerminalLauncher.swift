import Foundation
import AppKit

/// Launches SSH terminal sessions to Jetson devices.
@MainActor
final class TerminalLauncher {

    /// Available terminal apps on the system.
    static var availableTerminals: [TerminalApp] {
        var apps: [TerminalApp] = []

        let candidates: [(String, String, String)] = [
            ("Ghostty", "/Applications/Ghostty.app", "com.mitchellh.ghostty"),
            ("Terminal", "/System/Applications/Utilities/Terminal.app", "com.apple.Terminal"),
            ("iTerm", "/Applications/iTerm.app", "com.googlecode.iterm2"),
            ("Warp", "/Applications/Warp.app", "dev.warp.Warp-Stable"),
            ("Alacritty", "/Applications/Alacritty.app", "org.alacritty"),
            ("Kitty", "/Applications/kitty.app", "net.kovidgoyal.kitty"),
        ]

        for (name, path, bundleID) in candidates {
            if FileManager.default.fileExists(atPath: path) {
                apps.append(TerminalApp(name: name, path: path, bundleID: bundleID))
            }
        }

        return apps
    }

    /// Open an SSH session in the user's preferred terminal.
    static func openSSH(
        host: String,
        port: Int,
        username: String,
        terminalApp: TerminalApp? = nil
    ) {
        let sshCommand = "ssh -p \(port) \(username)@\(host)"
        let terminal = terminalApp ?? availableTerminals.first ?? TerminalApp(
            name: "Terminal",
            path: "/System/Applications/Utilities/Terminal.app",
            bundleID: "com.apple.Terminal"
        )

        switch terminal.bundleID {
        case "com.apple.Terminal":
            openInAppleTerminal(sshCommand)
        case "com.googlecode.iterm2":
            openInITerm(sshCommand)
        default:
            // Generic: open terminal app then run command via osascript
            openGeneric(sshCommand, app: terminal)
        }
    }

    /// Open a local terminal at a specific directory.
    static func openLocal(
        at directory: String = "~",
        terminalApp: TerminalApp? = nil
    ) {
        let terminal = terminalApp ?? availableTerminals.first ?? TerminalApp(
            name: "Terminal",
            path: "/System/Applications/Utilities/Terminal.app",
            bundleID: "com.apple.Terminal"
        )

        let cdCommand = "cd \(directory)"

        switch terminal.bundleID {
        case "com.apple.Terminal":
            openInAppleTerminal(cdCommand)
        default:
            openGeneric(cdCommand, app: terminal)
        }
    }

    // MARK: - Private

    private static func openInAppleTerminal(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        runAppleScript(script)
    }

    private static func openInITerm(_ command: String) {
        let script = """
        tell application "iTerm"
            activate
            create window with default profile command "\(command)"
        end tell
        """
        runAppleScript(script)
    }

    private static func openGeneric(_ command: String, app: TerminalApp) {
        // Open the terminal app, then use osascript to type the command
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let script = """
            tell application "System Events"
                tell process "\(app.name)"
                    set frontmost to true
                    keystroke "\(command)"
                    keystroke return
                end tell
            end tell
            """
            runAppleScript(script)
        }
    }

    private static func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error {
                print("[TerminalLauncher] AppleScript error: \(error)")
            }
        }
    }
}

struct TerminalApp: Identifiable, Hashable {
    var id: String { bundleID }
    let name: String
    let path: String
    let bundleID: String

    var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: path)
    }
}
