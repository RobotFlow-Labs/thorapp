import AppKit
import CryptoKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppUpdater {
    nonisolated static let bundleIdentifier = "com.robotflowlabs.thor"
    nonisolated static let appName = "THORApp"
    nonisolated static let updaterManifestName = "\(appName)-update.json"
    nonisolated static let githubLatestReleaseURL = URL(
        string: ProcessInfo.processInfo.environment["THOR_UPDATER_RELEASES_API_URL"]
            ?? "https://api.github.com/repos/RobotFlow-Labs/thorapp/releases/latest"
    )!
    nonisolated static let defaultInstallTargetURL = URL(fileURLWithPath: "/Applications/\(appName).app")

    private enum DefaultsKey {
        static let autoCheckEnabled = "updates.autoCheckEnabled"
        static let useLocalSource = "updates.useLocalSource"
        static let localSourcePath = "updates.localSourcePath"
    }

    enum UpdateSource: String, Sendable {
        case githubRelease
        case localBundle
        case localArchive
        case localManifest

        var label: String {
            switch self {
            case .githubRelease:
                return "GitHub release"
            case .localBundle:
                return "local app bundle"
            case .localArchive:
                return "local archive"
            case .localManifest:
                return "local update manifest"
            }
        }
    }

    enum PackageKind: String, Sendable {
        case appBundle
        case zipArchive
    }

    struct AppVersion: Comparable, Equatable, Sendable {
        let marketingVersion: String
        let build: Int

        var displayString: String {
            build > 0 ? "\(marketingVersion) (\(build))" : marketingVersion
        }

        static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
            let lhsComponents = normalizedComponents(for: lhs.marketingVersion)
            let rhsComponents = normalizedComponents(for: rhs.marketingVersion)

            for index in 0..<max(lhsComponents.count, rhsComponents.count) {
                let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
                let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0
                if lhsValue != rhsValue {
                    return lhsValue < rhsValue
                }
            }

            return lhs.build < rhs.build
        }

        private static func normalizedComponents(for version: String) -> [Int] {
            version
                .split(separator: ".")
                .compactMap { Int($0) }
        }
    }

    struct AvailableUpdate: Identifiable, Sendable {
        let version: AppVersion
        let source: UpdateSource
        let packageURL: URL
        let packageKind: PackageKind
        let expectedSHA256: String?
        let releasePageURL: URL?
        let sourceDescription: String

        var id: String {
            "\(source.rawValue)-\(version.displayString)-\(packageURL.absoluteString)"
        }
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    struct AlertState: Identifiable {
        enum Kind {
            case available(AvailableUpdate)
            case notice
        }

        let id = UUID()
        let title: String
        let message: String
        let kind: Kind
    }

    struct BundleMetadata: Sendable {
        let bundleIdentifier: String
        let version: AppVersion
    }

    private struct ReleaseManifest: Decodable {
        let bundleIdentifier: String
        let version: String
        let build: Int?
        let archiveName: String?
        let archiveURL: String?
        let sha256: String?
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL?
        let draft: Bool
        let prerelease: Bool
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let urlSession: URLSession
    private let environmentLocalSourcePath: String?
    private let environmentInstallerScriptPath: String?

    var autoCheckEnabled: Bool {
        didSet { userDefaults.set(autoCheckEnabled, forKey: DefaultsKey.autoCheckEnabled) }
    }

    var useLocalSource: Bool {
        didSet { userDefaults.set(useLocalSource, forKey: DefaultsKey.useLocalSource) }
    }

    var localSourcePath: String {
        didSet { userDefaults.set(localSourcePath, forKey: DefaultsKey.localSourcePath) }
    }

    private(set) var currentVersion: AppVersion
    private(set) var availableUpdate: AvailableUpdate?
    private(set) var isCheckingForUpdates = false
    private(set) var isInstallingUpdate = false
    private(set) var lastCheckedAt: Date?
    var alertState: AlertState?

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        urlSession: URLSession = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentBundle: Bundle = .main
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.urlSession = urlSession
        self.environmentLocalSourcePath = environment["THOR_UPDATER_LOCAL_SOURCE"]
        self.environmentInstallerScriptPath = environment["THOR_UPDATER_INSTALLER_SCRIPT"]
        self.autoCheckEnabled = userDefaults.object(forKey: DefaultsKey.autoCheckEnabled) as? Bool ?? true
        self.useLocalSource = userDefaults.bool(forKey: DefaultsKey.useLocalSource)
        self.localSourcePath = userDefaults.string(forKey: DefaultsKey.localSourcePath) ?? ""
        self.currentVersion = Self.version(for: currentBundle)
    }

    var effectiveLocalSourcePath: String {
        if let environmentLocalSourcePath, !environmentLocalSourcePath.isEmpty {
            return environmentLocalSourcePath
        }
        return localSourcePath
    }

    var localSourceIsOverriddenByEnvironment: Bool {
        if let environmentLocalSourcePath {
            return !environmentLocalSourcePath.isEmpty
        }
        return false
    }

    var canUseLocalSource: Bool {
        let path = effectiveLocalSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!path.isEmpty) && (useLocalSource || localSourceIsOverriddenByEnvironment)
    }

    func dismissAlert() {
        alertState = nil
    }

    func checkForUpdatesOnLaunch() async {
        guard autoCheckEnabled else { return }
        await checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer {
            isCheckingForUpdates = false
            lastCheckedAt = Date()
        }

        do {
            let candidate = try await resolveBestCandidate()
            guard let candidate else {
                availableUpdate = nil
                if userInitiated {
                    alertState = AlertState(
                        title: "THOR is Up to Date",
                        message: "No update sources are configured or available right now.",
                        kind: .notice
                    )
                }
                return
            }

            if candidate.version > currentVersion {
                availableUpdate = candidate
                alertState = AlertState(
                    title: "Update Available",
                    message: "THOR \(candidate.version.displayString) is available from \(candidate.sourceDescription). Install it into /Applications now?",
                    kind: .available(candidate)
                )
            } else {
                availableUpdate = nil
                if userInitiated {
                    alertState = AlertState(
                        title: "THOR is Up to Date",
                        message: "You are already running THOR \(currentVersion.displayString).",
                        kind: .notice
                    )
                }
            }
        } catch {
            if userInitiated {
                alertState = AlertState(
                    title: "Update Check Failed",
                    message: error.localizedDescription,
                    kind: .notice
                )
            }
        }
    }

    func installAvailableUpdate() async {
        guard !isInstallingUpdate, let update = availableUpdate else { return }
        isInstallingUpdate = true
        defer { isInstallingUpdate = false }

        do {
            let stagedAppURL = try await prepareStagedApp(for: update)
            try launchInstaller(stagedAppURL: stagedAppURL, targetAppURL: Self.defaultInstallTargetURL)
            alertState = nil
            NSApplication.shared.terminate(nil)
        } catch {
            alertState = AlertState(
                title: "Update Install Failed",
                message: error.localizedDescription,
                kind: .notice
            )
        }
    }

    private func resolveBestCandidate() async throws -> AvailableUpdate? {
        var candidates: [AvailableUpdate] = []

        if let localCandidate = try await loadLocalCandidateIfConfigured() {
            candidates.append(localCandidate)
        }

        if let githubCandidate = try await loadGitHubReleaseCandidate() {
            candidates.append(githubCandidate)
        }

        return candidates.max { lhs, rhs in
            lhs.version < rhs.version
        }
    }

    private func loadLocalCandidateIfConfigured() async throws -> AvailableUpdate? {
        guard canUseLocalSource else { return nil }

        let path = effectiveLocalSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        let sourceURL = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AppUpdaterError.localSourceMissing(path)
        }

        switch sourceURL.pathExtension.lowercased() {
        case "app":
            let metadata = try Self.readBundleMetadata(at: sourceURL)
            try Self.validateBundleIdentifier(metadata.bundleIdentifier)
            return AvailableUpdate(
                version: metadata.version,
                source: .localBundle,
                packageURL: sourceURL,
                packageKind: .appBundle,
                expectedSHA256: nil,
                releasePageURL: nil,
                sourceDescription: "the configured local app bundle"
            )

        case "zip":
            let version = try await inspectArchiveVersion(at: sourceURL)
            return AvailableUpdate(
                version: version,
                source: .localArchive,
                packageURL: sourceURL,
                packageKind: .zipArchive,
                expectedSHA256: nil,
                releasePageURL: nil,
                sourceDescription: "the configured local archive"
            )

        case "json":
            let manifest = try Self.readManifest(from: sourceURL)
            return try resolveManifestUpdate(
                manifest,
                source: .localManifest,
                manifestURL: sourceURL,
                releasePageURL: nil,
                releaseAssetsByName: [:]
            )

        default:
            throw AppUpdaterError.unsupportedLocalSource(sourceURL.lastPathComponent)
        }
    }

    private func loadGitHubReleaseCandidate() async throws -> AvailableUpdate? {
        let (data, response) = try await urlSession.data(from: Self.githubLatestReleaseURL)
        try Self.validateHTTPResponse(response)

        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }

        let assetsByName = Dictionary(uniqueKeysWithValues: release.assets.map { ($0.name, $0.browserDownloadURL) })

        if let manifestURL = assetsByName[Self.updaterManifestName] {
            let manifest = try await fetchManifest(from: manifestURL)
            return try resolveManifestUpdate(
                manifest,
                source: .githubRelease,
                manifestURL: manifestURL,
                releasePageURL: release.htmlURL,
                releaseAssetsByName: assetsByName
            )
        }

        guard let archiveAsset = Self.selectBestReleaseArchive(from: release.assets) else { return nil }

        let checksum: String?
        if let checksumsURL = assetsByName["SHA256SUMS.txt"] {
            checksum = try await fetchChecksum(for: archiveAsset.name, from: checksumsURL)
        } else {
            checksum = nil
        }

        return AvailableUpdate(
            version: AppVersion(marketingVersion: Self.versionString(from: release.tagName), build: 0),
            source: .githubRelease,
            packageURL: archiveAsset.browserDownloadURL,
            packageKind: .zipArchive,
            expectedSHA256: checksum,
            releasePageURL: release.htmlURL,
            sourceDescription: "the latest GitHub release"
        )
    }

    private func resolveManifestUpdate(
        _ manifest: ReleaseManifest,
        source: UpdateSource,
        manifestURL: URL,
        releasePageURL: URL?,
        releaseAssetsByName: [String: URL]
    ) throws -> AvailableUpdate {
        try Self.validateBundleIdentifier(manifest.bundleIdentifier)

        let packageURL = try Self.resolveManifestPackageURL(
            manifest,
            manifestURL: manifestURL,
            releaseAssetsByName: releaseAssetsByName
        )
        let packageKind = Self.packageKind(for: packageURL)
        let sourceDescription: String
        switch source {
        case .githubRelease:
            sourceDescription = "the GitHub release manifest"
        case .localBundle, .localArchive, .localManifest:
            sourceDescription = "the configured local update manifest"
        }

        return AvailableUpdate(
            version: AppVersion(
                marketingVersion: manifest.version,
                build: manifest.build ?? 0
            ),
            source: source,
            packageURL: packageURL,
            packageKind: packageKind,
            expectedSHA256: manifest.sha256,
            releasePageURL: releasePageURL,
            sourceDescription: sourceDescription
        )
    }

    private func fetchManifest(from url: URL) async throws -> ReleaseManifest {
        let (data, response) = try await urlSession.data(from: url)
        try Self.validateHTTPResponse(response)
        return try JSONDecoder().decode(ReleaseManifest.self, from: data)
    }

    private func fetchChecksum(for archiveName: String, from url: URL) async throws -> String? {
        let (data, response) = try await urlSession.data(from: url)
        try Self.validateHTTPResponse(response)
        guard let contents = String(data: data, encoding: .utf8) else {
            throw AppUpdaterError.invalidChecksumFile
        }
        return Self.sha256(for: archiveName, in: contents)
    }

    private func inspectArchiveVersion(at archiveURL: URL) async throws -> AppVersion {
        let metadata = try await Task.detached(priority: .utility) {
            let stagingRoot = try Self.makeTemporaryDirectory(prefix: "thor-update-inspect-")
            defer { try? FileManager.default.removeItem(at: stagingRoot) }

            let extractedAppURL = try Self.extractAppBundle(from: archiveURL, to: stagingRoot)
            return try Self.readBundleMetadata(at: extractedAppURL)
        }.value

        try Self.validateBundleIdentifier(metadata.bundleIdentifier)
        return metadata.version
    }

    private func prepareStagedApp(for update: AvailableUpdate) async throws -> URL {
        let workingRoot = try Self.makeTemporaryDirectory(prefix: "thor-update-stage-")
        let localPackageURL: URL

        if update.packageURL.isFileURL {
            localPackageURL = update.packageURL
        } else {
            let (temporaryDownloadURL, response) = try await urlSession.download(from: update.packageURL)
            try Self.validateHTTPResponse(response)
            let archiveCopyURL = workingRoot.appendingPathComponent(update.packageURL.lastPathComponent)
            if fileManager.fileExists(atPath: archiveCopyURL.path) {
                try fileManager.removeItem(at: archiveCopyURL)
            }
            try fileManager.moveItem(at: temporaryDownloadURL, to: archiveCopyURL)
            localPackageURL = archiveCopyURL
        }

        return try await Task.detached(priority: .userInitiated) {
            try Self.stagePackage(
                localPackageURL,
                kind: update.packageKind,
                expectedSHA256: update.expectedSHA256,
                in: workingRoot
            )
        }.value
    }

    private func launchInstaller(stagedAppURL: URL, targetAppURL: URL) throws {
        let installerScriptURL = try resolveInstallerScriptURL()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            installerScriptURL.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            stagedAppURL.path,
            targetAppURL.path,
        ]
        try process.run()
    }

    private func resolveInstallerScriptURL() throws -> URL {
        let candidates = [
            environmentInstallerScriptPath.map { URL(fileURLWithPath: $0) },
            Bundle.main.resourceURL?.appendingPathComponent("install_update.sh"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Sources/THORApp/Resources/install_update.sh"),
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw AppUpdaterError.installerScriptMissing
    }

    nonisolated static func version(for bundle: Bundle) -> AppVersion {
        let marketingVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let buildValue = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return AppVersion(marketingVersion: marketingVersion, build: Int(buildValue ?? "") ?? 0)
    }

    nonisolated static func readBundleMetadata(at appURL: URL) throws -> BundleMetadata {
        let infoPlistURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]

        guard
            let plist,
            let bundleIdentifier = plist["CFBundleIdentifier"] as? String,
            let marketingVersion = plist["CFBundleShortVersionString"] as? String
        else {
            throw AppUpdaterError.invalidBundle(appURL.lastPathComponent)
        }

        let build = Int((plist["CFBundleVersion"] as? String) ?? "") ?? 0
        return BundleMetadata(
            bundleIdentifier: bundleIdentifier,
            version: AppVersion(marketingVersion: marketingVersion, build: build)
        )
    }

    nonisolated static func sha256(for artifactName: String, in checksumContents: String) -> String? {
        for line in checksumContents.split(whereSeparator: \.isNewline) {
            let components = line.split(whereSeparator: \.isWhitespace)
            guard components.count >= 2 else { continue }
            if components.last.map(String.init) == artifactName {
                return String(components[0])
            }
        }
        return nil
    }

    nonisolated private static func validateBundleIdentifier(_ bundleIdentifier: String) throws {
        guard bundleIdentifier == Self.bundleIdentifier else {
            throw AppUpdaterError.invalidBundleIdentifier(bundleIdentifier)
        }
    }

    nonisolated private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdaterError.remoteRequestFailed(httpResponse.statusCode)
        }
    }

    nonisolated private static func readManifest(from url: URL) throws -> ReleaseManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ReleaseManifest.self, from: data)
    }

    nonisolated private static func resolveManifestPackageURL(
        _ manifest: ReleaseManifest,
        manifestURL: URL,
        releaseAssetsByName: [String: URL]
    ) throws -> URL {
        if
            let archiveURL = manifest.archiveURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            !archiveURL.isEmpty
        {
            if let absoluteURL = URL(string: archiveURL), absoluteURL.scheme != nil {
                return absoluteURL
            }

            let baseURL = manifestURL.deletingLastPathComponent()
            return URL(fileURLWithPath: archiveURL, relativeTo: baseURL).standardizedFileURL
        }

        if
            let archiveName = manifest.archiveName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !archiveName.isEmpty
        {
            if let releaseAssetURL = releaseAssetsByName[archiveName] {
                return releaseAssetURL
            }

            let baseURL = manifestURL.deletingLastPathComponent()
            return baseURL.appendingPathComponent(archiveName).standardizedFileURL
        }

        throw AppUpdaterError.manifestMissingArchive
    }

    nonisolated private static func packageKind(for url: URL) -> PackageKind {
        url.pathExtension.lowercased() == "app" ? .appBundle : .zipArchive
    }

    nonisolated private static func selectBestReleaseArchive(from assets: [GitHubAsset]) -> GitHubAsset? {
        let zipAssets = assets.filter {
            $0.name.hasSuffix(".zip") && $0.name.contains(appName)
        }
        guard !zipAssets.isEmpty else { return nil }

        let preferredSuffixes = [
            "-\(preferredArchitectureTag).zip",
            "-universal.zip",
        ]

        for suffix in preferredSuffixes {
            if let asset = zipAssets.first(where: { $0.name.hasSuffix(suffix) }) {
                return asset
            }
        }

        return zipAssets.first
    }

    nonisolated private static var preferredArchitectureTag: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "universal"
        #endif
    }

    nonisolated private static func versionString(from tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    nonisolated private static func makeTemporaryDirectory(prefix: String) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let directory = temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated private static func stagePackage(
        _ packageURL: URL,
        kind: PackageKind,
        expectedSHA256: String?,
        in workingRoot: URL
    ) throws -> URL {
        if let expectedSHA256, kind == .zipArchive {
            try verifySHA256(of: packageURL, expected: expectedSHA256)
        }

        let stagedAppURL = workingRoot.appendingPathComponent("\(appName).app")
        if FileManager.default.fileExists(atPath: stagedAppURL.path) {
            try FileManager.default.removeItem(at: stagedAppURL)
        }

        switch kind {
        case .appBundle:
            try copyItem(at: packageURL, to: stagedAppURL)

        case .zipArchive:
            let extractedAppURL = try extractAppBundle(from: packageURL, to: workingRoot)
            if extractedAppURL.standardizedFileURL != stagedAppURL.standardizedFileURL {
                try copyItem(at: extractedAppURL, to: stagedAppURL)
            }
        }

        let metadata = try readBundleMetadata(at: stagedAppURL)
        try validateBundleIdentifier(metadata.bundleIdentifier)
        return stagedAppURL
    }

    nonisolated private static func extractAppBundle(from archiveURL: URL, to directory: URL) throws -> URL {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, directory.path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AppUpdaterError.archiveExtractionFailed(output.isEmpty ? archiveURL.lastPathComponent : output)
        }

        return try findAppBundle(in: directory)
    }

    nonisolated private static func findAppBundle(in directory: URL) throws -> URL {
        if directory.pathExtension.lowercased() == "app" {
            return directory
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AppUpdaterError.invalidArchive(directory.lastPathComponent)
        }

        for case let candidate as URL in enumerator {
            if candidate.pathExtension.lowercased() == "app" {
                return candidate
            }
        }

        throw AppUpdaterError.invalidArchive(directory.lastPathComponent)
    }

    nonisolated private static func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    nonisolated private static func verifySHA256(of fileURL: URL, expected: String) throws {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.lowercased() == expected.lowercased() else {
            throw AppUpdaterError.invalidChecksum
        }
    }
}

enum AppUpdaterError: LocalizedError {
    case archiveExtractionFailed(String)
    case installerScriptMissing
    case invalidArchive(String)
    case invalidBundle(String)
    case invalidBundleIdentifier(String)
    case invalidChecksum
    case invalidChecksumFile
    case localSourceMissing(String)
    case manifestMissingArchive
    case remoteRequestFailed(Int)
    case unsupportedLocalSource(String)

    var errorDescription: String? {
        switch self {
        case .archiveExtractionFailed(let detail):
            return "THOR could not unpack the update archive: \(detail)"
        case .installerScriptMissing:
            return "The THOR updater helper script is missing from the app bundle."
        case .invalidArchive(let name):
            return "The update archive \(name) does not contain a THOR app bundle."
        case .invalidBundle(let name):
            return "The update bundle \(name) is missing version metadata."
        case .invalidBundleIdentifier(let bundleIdentifier):
            return "The update bundle has an unexpected bundle identifier: \(bundleIdentifier)"
        case .invalidChecksum:
            return "The downloaded update did not match its expected checksum."
        case .invalidChecksumFile:
            return "THOR could not read the release checksum list."
        case .localSourceMissing(let path):
            return "The configured local update source is missing: \(path)"
        case .manifestMissingArchive:
            return "The update manifest does not point to an archive or app bundle."
        case .remoteRequestFailed(let statusCode):
            return "The update server returned HTTP \(statusCode)."
        case .unsupportedLocalSource(let name):
            return "Local update sources must be a `.app`, `.zip`, or `\(AppUpdater.updaterManifestName)` file. Received \(name)."
        }
    }
}
