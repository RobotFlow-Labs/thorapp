import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            ConnectionSettingsView()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
        }
        .frame(width: 450, height: 300)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
        }
        .formStyle(.grouped)
    }
}

private struct ConnectionSettingsView: View {
    @AppStorage("defaultSSHPort") private var defaultSSHPort = "22"
    @AppStorage("defaultUsername") private var defaultUsername = "jetson"
    @AppStorage("connectionTimeout") private var connectionTimeout = "10"

    var body: some View {
        Form {
            TextField("Default SSH Port", text: $defaultSSHPort)
            TextField("Default Username", text: $defaultUsername)
            TextField("Connection Timeout (s)", text: $connectionTimeout)
        }
        .formStyle(.grouped)
    }
}
