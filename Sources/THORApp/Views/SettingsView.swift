import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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

            UpdateSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .environment(appState)
        .frame(width: 560, height: 420)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage(THORWorkspacePreferences.showDockerToolsKey) private var showDockerTools = true
    @AppStorage(THORWorkspacePreferences.showTabGuidanceKey) private var showTabGuidance = true

    var body: some View {
        Form {
            Section("App") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            }

            Section("Workspace") {
                Toggle("Show Docker and simulator tools", isOn: $showDockerTools)
                Text("Turn this off when you want THOR to focus on real-device workflows without the Docker tab or Docker readiness noise.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Open tabs with help visible", isOn: $showTabGuidance)
                Text("Each device tab can open with a short operator guide that explains what the page is for and what to do next.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

private struct UpdateSettingsView: View {
    @Environment(AppState.self) private var appState

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { appState.updater.autoCheckEnabled },
            set: { appState.updater.autoCheckEnabled = $0 }
        )
    }

    private var useLocalSourceBinding: Binding<Bool> {
        Binding(
            get: { appState.updater.useLocalSource },
            set: { appState.updater.useLocalSource = $0 }
        )
    }

    private var localSourcePathBinding: Binding<String> {
        Binding(
            get: { appState.updater.localSourcePath },
            set: { appState.updater.localSourcePath = $0 }
        )
    }

    var body: some View {
        Form {
            Section("Installed Version") {
                LabeledContent("Current build") {
                    Text(appState.updater.currentVersion.displayString)
                        .textSelection(.enabled)
                }

                if let lastCheckedAt = appState.updater.lastCheckedAt {
                    LabeledContent("Last checked") {
                        Text(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Checks") {
                Toggle("Automatically check on launch", isOn: autoCheckBinding)

                HStack {
                    Button("Check Now") {
                        Task {
                            await appState.checkForUpdates(userInitiated: true)
                        }
                    }
                    .disabled(appState.updater.isCheckingForUpdates || appState.updater.isInstallingUpdate)

                    if appState.updater.isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Local Source") {
                Toggle("Enable local update source", isOn: useLocalSourceBinding)
                    .disabled(appState.updater.localSourceIsOverriddenByEnvironment)

                TextField("Local update path", text: localSourcePathBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(appState.updater.localSourceIsOverriddenByEnvironment)

                HStack {
                    Button("Browse…") {
                        chooseLocalUpdateSource()
                    }
                    .disabled(appState.updater.localSourceIsOverriddenByEnvironment)

                    Button("Clear") {
                        appState.updater.localSourcePath = ""
                    }
                    .disabled(appState.updater.localSourceIsOverriddenByEnvironment || appState.updater.localSourcePath.isEmpty)
                }

                Text("Supports a local `.app`, `.zip`, or `THORApp-update.json` file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if appState.updater.localSourceIsOverriddenByEnvironment {
                    Text("A `THOR_UPDATER_LOCAL_SOURCE` environment override is active for this app launch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let update = appState.updater.availableUpdate {
                Section("Available Update") {
                    LabeledContent("Version") {
                        Text(update.version.displayString)
                    }

                    LabeledContent("Source") {
                        Text(update.source.label)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Package") {
                        Text(update.packageURL.lastPathComponent)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Button("Install into /Applications") {
                            Task {
                                await appState.installAvailableUpdate()
                            }
                        }
                        .disabled(appState.updater.isInstallingUpdate)

                        if let releasePageURL = update.releasePageURL {
                            Button("Open Release Notes") {
                                NSWorkspace.shared.open(releasePageURL)
                            }
                        }

                        if appState.updater.isInstallingUpdate {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseLocalUpdateSource() {
        let panel = NSOpenPanel()
        panel.title = "Select a Local THOR Update Source"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle, .zip, .json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.updater.localSourcePath = url.path
        appState.updater.useLocalSource = true
    }
}
