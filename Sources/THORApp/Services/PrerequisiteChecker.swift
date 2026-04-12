import Foundation
import THORShared

/// Checks system prerequisites for THOR to function.
@MainActor
final class PrerequisiteChecker {

    struct CheckResult: Identifiable {
        let id = UUID()
        let name: String
        let status: CheckStatus
        let detail: String
    }

    enum CheckStatus {
        case pass
        case warning
        case fail
    }

    /// Run all prerequisite checks.
    func runAll() async -> [CheckResult] {
        var results: [CheckResult] = []

        // 1. SSH available
        results.append(await checkSSH())

        // 2. rsync available
        results.append(await checkRsync())

        // 3. Docker available (optional)
        results.append(await checkDocker())

        // 4. Database writable
        results.append(checkDatabasePath())

        // 5. Keychain accessible
        results.append(checkKeychain())

        return results
    }

    private func checkSSH() async -> CheckResult {
        let exists = FileManager.default.fileExists(atPath: "/usr/bin/ssh")
        if exists {
            return CheckResult(name: "SSH Client", status: .pass, detail: "OpenSSH available at /usr/bin/ssh")
        }
        return CheckResult(name: "SSH Client", status: .fail, detail: "SSH not found. Install Xcode Command Line Tools.")
    }

    private func checkRsync() async -> CheckResult {
        let exists = FileManager.default.fileExists(atPath: "/usr/bin/rsync")
        if exists {
            return CheckResult(name: "rsync", status: .pass, detail: "Available for delta file sync")
        }
        return CheckResult(name: "rsync", status: .warning, detail: "rsync not found. File sync will use scp fallback.")
    }

    private func checkDocker() async -> CheckResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return CheckResult(name: "Docker", status: .pass, detail: version)
            }
        } catch {}
        return CheckResult(name: "Docker", status: .warning, detail: "Docker not found. Jetson simulator requires Docker Desktop.")
    }

    private func checkDatabasePath() -> CheckResult {
        let thorDir = DatabaseManager.supportDirectoryURL
        let override = ProcessInfo.processInfo.environment[DatabaseManager.supportDirectoryEnvironmentKey]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let isTemporaryFallback = override == nil && thorDir.path.hasPrefix(FileManager.default.temporaryDirectory.path)

        do {
            try FileManager.default.createDirectory(at: thorDir, withIntermediateDirectories: true)
            if isTemporaryFallback {
                return CheckResult(
                    name: "Database",
                    status: .warning,
                    detail: "Application Support is unavailable; THOR is using temporary storage at \(thorDir.path)"
                )
            }
            return CheckResult(name: "Database", status: .pass, detail: "Writable at \(thorDir.path)")
        } catch {
            return CheckResult(name: "Database", status: .fail, detail: "Cannot write to \(thorDir.path): \(error.localizedDescription)")
        }
    }

    private func checkKeychain() -> CheckResult {
        // Try a dummy Keychain operation
        let testKey = "com.robotflowlabs.thor.prereq-test"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKey,
            kSecAttrAccount as String: "test",
            kSecValueData as String: Data("test".utf8),
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)

        // Clean up
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKey,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        if addStatus == errSecSuccess || addStatus == errSecDuplicateItem {
            return CheckResult(name: "Keychain", status: .pass, detail: "macOS Keychain accessible")
        }
        return CheckResult(name: "Keychain", status: .fail, detail: "Keychain access denied (status: \(addStatus))")
    }
}
