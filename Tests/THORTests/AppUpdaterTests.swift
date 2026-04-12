import Foundation
import Testing
@testable import THORApp

struct AppUpdaterTests {
    @Test("App versions compare marketing version before build number")
    func versionComparison() {
        let current = AppUpdater.AppVersion(marketingVersion: "0.1.0", build: 5)
        let newerBuild = AppUpdater.AppVersion(marketingVersion: "0.1.0", build: 6)
        let newerMarketing = AppUpdater.AppVersion(marketingVersion: "0.2.0", build: 1)

        #expect(current < newerBuild)
        #expect(newerBuild < newerMarketing)
    }

    @Test("Bundle metadata inspection reads THOR app version from Info.plist")
    func bundleMetadataInspection() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("thor-updater-tests-\(UUID().uuidString)")
        let appURL = tempRoot.appendingPathComponent("THORApp.app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.robotflowlabs.thor",
            "CFBundleShortVersionString": "0.3.0",
            "CFBundleVersion": "7",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let metadata = try AppUpdater.readBundleMetadata(at: appURL)
        #expect(metadata.bundleIdentifier == "com.robotflowlabs.thor")
        #expect(metadata.version == AppUpdater.AppVersion(marketingVersion: "0.3.0", build: 7))
    }

    @Test("Checksum parsing returns the matching app archive hash")
    func checksumParsing() {
        let checksums = """
        abc123  THORApp-0.1.0-macos-arm64.zip
        def456  thorctl-0.1.0-macos-arm64.tar.gz
        """

        #expect(AppUpdater.sha256(for: "THORApp-0.1.0-macos-arm64.zip", in: checksums) == "abc123")
        #expect(AppUpdater.sha256(for: "missing.zip", in: checksums) == nil)
    }
}
