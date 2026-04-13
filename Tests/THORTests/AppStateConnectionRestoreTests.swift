import Testing
@testable import THORApp
@testable import THORShared

@MainActor
@Suite("AppState Connection Restore Tests")
struct AppStateConnectionRestoreTests {

    @Test("Local simulator uses configured agent port for direct restore")
    func preferredDirectAgentPortUsesConfig() {
        let appState = AppState()
        let device = Device(id: 1, displayName: "Jetson Thor Sim", hostname: "localhost")
        let config = DeviceConfig(deviceID: 1, sshPort: 2222, agentPort: 8471)

        #expect(appState.preferredDirectAgentPort(for: device, config: config) == 8471)
    }

    @Test("Remote devices do not use direct restore ports")
    func preferredDirectAgentPortIgnoresRemoteHosts() {
        let appState = AppState()
        let device = Device(id: 2, displayName: "Lab Thor", hostname: "192.168.1.42")
        let config = DeviceConfig(deviceID: 2, sshPort: 22, agentPort: 8470)

        #expect(appState.preferredDirectAgentPort(for: device, config: config) == nil)
    }

    @Test("Persisted connected status restores even when auto-connect is disabled")
    func connectedStateStillRestores() {
        let appState = AppState()
        appState.connectionStates[7] = ConnectionState(deviceID: 7, status: .connected)

        let config = DeviceConfig(deviceID: 7, autoConnect: false)
        #expect(appState.shouldRestoreConnection(for: 7, config: config))
    }

    @Test("Auto-connect restores when the device was not previously connected")
    func autoConnectRestoresDisconnectedDevice() {
        let appState = AppState()
        appState.connectionStates[9] = ConnectionState(deviceID: 9, status: .disconnected)

        let config = DeviceConfig(deviceID: 9, autoConnect: true)
        #expect(appState.shouldRestoreConnection(for: 9, config: config))
    }
}
