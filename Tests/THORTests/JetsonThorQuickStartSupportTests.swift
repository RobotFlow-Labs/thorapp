import Testing
@testable import THORShared

@Suite("Jetson Thor Quick Start Support Tests")
struct JetsonThorQuickStartSupportTests {
    @Test("Second usbserial port is preferred for factory UEFI")
    func recommendsSecondDebugTTY() {
        let paths = [
            "/dev/cu.usbserial-0004",
            "/dev/cu.usbserial-0002",
            "/dev/cu.usbserial-0001",
            "/dev/cu.usbserial-0003",
        ]

        let recommended = JetsonThorQuickStartSupport.recommendedDebugSerialPath(from: paths)

        #expect(recommended == "/dev/cu.usbserial-0002")
    }

    @Test("First usbmodem port is preferred for oem-config")
    func recommendsFirstOEMTTY() {
        let paths = [
            "/dev/cu.usbmodem-03",
            "/dev/cu.usbmodem-01",
        ]

        let recommended = JetsonThorQuickStartSupport.recommendedOEMConfigPath(from: paths)

        #expect(recommended == "/dev/cu.usbmodem-01")
    }

    @Test("Ed25519 key is preferred over generated and RSA keys")
    func recommendsBestPublicKey() {
        let paths = [
            "/Users/test/.ssh/id_rsa.pub",
            "/Users/test/.ssh/thor_jetson_abcd1234.pub",
            "/Users/test/.ssh/id_ed25519.pub",
        ]

        let recommended = JetsonThorQuickStartSupport.recommendedPublicKeyPath(from: paths)

        #expect(recommended == "/Users/test/.ssh/id_ed25519.pub")
    }

    @Test("USB tether detection keys off 192.168.55.x")
    func detectsUSBTetherAddresses() {
        let detected = JetsonThorQuickStartSupport.usbTetherDetected(
            addresses: ["10.0.0.18", "192.168.55.100", "127.0.0.1"]
        )

        #expect(detected)
        #expect(JetsonThorQuickStartSupport.isJetsonUSBTetherAddress("192.168.55.1"))
        #expect(!JetsonThorQuickStartSupport.isJetsonUSBTetherAddress("169.254.1.5"))
    }

    @Test("Generated commands use documented baud rates and addresses")
    func generatesConsoleAndSSHCommands() {
        let uefi = JetsonThorQuickStartSupport.uefiConsoleCommand(serialPath: "/dev/cu.usbserial-0002")
        let oem = JetsonThorQuickStartSupport.oemConfigConsoleCommand(serialPath: "/dev/cu.usbmodem-123")
        let ssh = JetsonThorQuickStartSupport.usbSSHCommand(
            username: "nvidia",
            identityPath: "/Users/test/.ssh/id_ed25519"
        )

        #expect(uefi.contains("9600"))
        #expect(uefi.contains("242"))
        #expect(oem.contains("115200"))
        #expect(ssh.contains("nvidia@192.168.55.1"))
        #expect(ssh.contains("/Users/test/.ssh/id_ed25519"))
    }
}
