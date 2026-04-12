import Foundation
import Testing
@testable import THORShared

@Suite("Jetson Thor Production Readiness Tests")
struct JetsonThorProductionReadinessTests {
    @Test("Host snapshot prefers the documented setup devices and keys")
    func snapshotPrioritizesSetupHardware() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sshDir = home.appendingPathComponent(".ssh")

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sshDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: home)
        }

        let devNames = [
            "cu.usbserial-0001",
            "cu.usbserial-0002",
            "cu.usbserial-0004",
            "cu.usbmodem-0001",
        ]
        for name in devNames {
            fileManager.createFile(atPath: root.appendingPathComponent(name).path, contents: nil)
        }

        let keyNames = [
            "id_rsa.pub",
            "thor_jetson_lab.pub",
            "id_ed25519.pub",
        ]
        for name in keyNames {
            fileManager.createFile(atPath: sshDir.appendingPathComponent(name).path, contents: nil)
        }

        let support = JetsonThorQuickStartSupport(
            devRoot: root.path,
            homeDirectory: home.path,
            interfaceAddressesOverride: [
                "169.254.1.5",
                "192.168.55.1",
                "10.0.0.8",
                "192.168.55.42",
            ]
        )

        let snapshot = support.snapshot()

        #expect(snapshot.debugSerialCandidates.map(\.path) == [
            "\(root.path)/cu.usbserial-0001",
            "\(root.path)/cu.usbserial-0002",
            "\(root.path)/cu.usbserial-0004",
        ])
        #expect(snapshot.debugSerialCandidates.first(where: { $0.recommended })?.path == "\(root.path)/cu.usbserial-0002")
        #expect(snapshot.oemConfigCandidates.map(\.path) == ["\(root.path)/cu.usbmodem-0001"])
        #expect(snapshot.oemConfigCandidates.first?.recommended == true)
        #expect(snapshot.publicKeyCandidates.first?.path.hasSuffix("/.ssh/id_ed25519.pub") == true)
        #expect(snapshot.publicKeyCandidates.first?.recommended == true)
        #expect(snapshot.usbTetherHostAddresses == ["192.168.55.1", "192.168.55.42"])
        #expect(snapshot.usbTetherDetected)
    }

    @Test("Shell command helpers preserve quoting for spaces and apostrophes")
    func commandHelpersQuoteArgumentsSafely() {
        let ssh = JetsonThorQuickStartSupport.sshCommand(
            username: "thor.user",
            host: "192.168.55.1",
            identityPath: "/Users/test/My Keys/id_ed25519",
            remoteCommand: "echo 'ready' && uname -a"
        )

        let install = JetsonThorQuickStartSupport.jetPackInstallCommand(
            username: "thor.user",
            identityPath: "/Users/test/My Keys/id_ed25519"
        )

        let smoke = JetsonThorQuickStartSupport.dockerSmokeTestCommand(
            username: "thor.user",
            identityPath: "/Users/test/My Keys/id_ed25519"
        )

        #expect(ssh.contains("thor.user@192.168.55.1"))
        #expect(ssh.contains("-i '/Users/test/My Keys/id_ed25519'"))
        #expect(ssh.contains("'echo '\"'\"'ready'\"'\"' && uname -a'"))
        #expect(install.contains("sudo apt update && sudo apt install -y nvidia-jetpack"))
        #expect(smoke.contains("docker --version && sudo systemctl status docker --no-pager"))
        #expect(install.contains("-i '/Users/test/My Keys/id_ed25519'"))
        #expect(smoke.contains("-i '/Users/test/My Keys/id_ed25519'"))
    }

    @Test("Readiness defaults and ranks are stable for setup UX")
    func readinessDefaultsAndOrderingStayStable() {
        let matrix = CapabilityMatrix(connectionMode: "usb", features: [
            "docker": CapabilityGate(state: .supported, reason: "Docker is ready.", actionLabel: nil),
        ])

        let missing = matrix.gate(for: "ros2")
        let present = matrix.gate(for: "docker")

        #expect(missing.state == .needsSetup)
        #expect(missing.reason == "Capability not evaluated yet.")
        #expect(missing.actionLabel == "Run setup")
        #expect(present.state == .supported)
        #expect(CapabilityState.supported.rank < CapabilityState.degraded.rank)
        #expect(CapabilityState.degraded.rank < CapabilityState.needsSetup.rank)
        #expect(CapabilityState.needsSetup.rank < CapabilityState.unsupported.rank)
        #expect(ReadinessStatus.ready.rank < ReadinessStatus.warning.rank)
        #expect(ReadinessStatus.warning.rank < ReadinessStatus.unknown.rank)
        #expect(ReadinessStatus.unknown.rank < ReadinessStatus.blocked.rank)

        let result = SetupCheckResult(
            stage: "Docker",
            status: .warning,
            reason: "Docker is installed but inactive.",
            actionLabel: "Start Docker",
            rawDetails: "inactive"
        )

        #expect(result.id == "Docker")
        #expect(result.actionLabel == "Start Docker")
        #expect(result.rawDetails == "inactive")
    }

    @Test("Guided flow status raw values remain compatible with persisted data")
    func guidedFlowStatusRawValuesAreStable() {
        #expect(GuidedFlowStatus.notStarted.rawValue == "not_started")
        #expect(GuidedFlowStatus.inProgress.rawValue == "in_progress")
        #expect(GuidedFlowStatus.completed.rawValue == "completed")
        #expect(GuidedFlowStatus.allCases.count == 3)
    }
}
