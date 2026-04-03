import Foundation
import Security

/// Manages SSH credentials in macOS Keychain.
public struct KeychainManager: Sendable {
    private let servicePrefix = "com.robotflowlabs.thor"

    public init() {}

    // MARK: - SSH Key References

    /// Store an SSH private key path reference for a device.
    public func storeSSHKeyPath(_ path: String, for deviceID: Int64) throws {
        let key = "\(servicePrefix).sshkey.\(deviceID)"
        try store(value: path, for: key)
    }

    /// Retrieve the SSH private key path for a device.
    public func sshKeyPath(for deviceID: Int64) -> String? {
        let key = "\(servicePrefix).sshkey.\(deviceID)"
        return retrieve(for: key)
    }

    // MARK: - SSH Passwords (bootstrap fallback)

    /// Store an SSH password for a device (bootstrap only).
    public func storePassword(_ password: String, for deviceID: Int64) throws {
        let key = "\(servicePrefix).password.\(deviceID)"
        try store(value: password, for: key)
    }

    /// Retrieve SSH password for a device.
    public func password(for deviceID: Int64) -> String? {
        let key = "\(servicePrefix).password.\(deviceID)"
        return retrieve(for: key)
    }

    // MARK: - SSH Passphrases

    /// Store an SSH key passphrase for a device.
    public func storePassphrase(_ passphrase: String, for deviceID: Int64) throws {
        let key = "\(servicePrefix).passphrase.\(deviceID)"
        try store(value: passphrase, for: key)
    }

    /// Retrieve SSH key passphrase for a device.
    public func passphrase(for deviceID: Int64) -> String? {
        let key = "\(servicePrefix).passphrase.\(deviceID)"
        return retrieve(for: key)
    }

    // MARK: - Cleanup

    /// Remove all credentials for a device.
    public func removeCredentials(for deviceID: Int64) {
        let keys = [
            "\(servicePrefix).sshkey.\(deviceID)",
            "\(servicePrefix).password.\(deviceID)",
            "\(servicePrefix).passphrase.\(deviceID)",
        ]
        for key in keys {
            delete(for: key)
        }
    }

    // MARK: - Registry Credentials

    /// Store a registry password for a profile.
    public func storeRegistryPassword(_ password: String, for profileID: Int64) throws {
        let key = "\(servicePrefix).registry.password.\(profileID)"
        try store(value: password, for: key)
    }

    /// Retrieve a registry password for a profile.
    public func registryPassword(for profileID: Int64) -> String? {
        let key = "\(servicePrefix).registry.password.\(profileID)"
        return retrieve(for: key)
    }

    /// Remove registry secrets for a profile.
    public func removeRegistrySecrets(for profileID: Int64) {
        delete(for: "\(servicePrefix).registry.password.\(profileID)")
    }

    // MARK: - Private

    private func store(value: String, for account: String) throws {
        let data = Data(value.utf8)

        // Delete existing first
        delete(for: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    private func retrieve(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func delete(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainError: Error, LocalizedError {
    case storeFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Keychain store failed with status: \(status)"
        }
    }
}
