import Foundation

enum THORWorkspacePreferences {
    static let showDockerToolsKey = "showDockerTools"
    static let showTabGuidanceKey = "showTabGuidance"

    static func showDockerTools(in defaults: UserDefaults = .standard) -> Bool {
        boolValue(forKey: showDockerToolsKey, default: true, in: defaults)
    }

    static func showTabGuidance(in defaults: UserDefaults = .standard) -> Bool {
        boolValue(forKey: showTabGuidanceKey, default: true, in: defaults)
    }

    private static func boolValue(forKey key: String, default defaultValue: Bool, in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}
