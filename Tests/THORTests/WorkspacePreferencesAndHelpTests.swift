import Foundation
import Testing
@testable import THORApp

@Suite("Workspace Preferences and Help Tests")
struct WorkspacePreferencesAndHelpTests {

    @Test("Docker tools preference defaults to visible")
    func showDockerToolsDefaultsToVisible() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        #expect(THORWorkspacePreferences.showDockerTools(in: defaults))
    }

    @Test("Tab guidance preference defaults to visible")
    func showTabGuidanceDefaultsToVisible() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        #expect(THORWorkspacePreferences.showTabGuidance(in: defaults))
    }

    @Test("Every device tab exposes operator help")
    func everyTabHasHelpContent() {
        for tab in DetailTab.allCases {
            let help = tab.help
            #expect(!help.title.isEmpty)
            #expect(!help.summary.isEmpty)
            #expect(!help.startHere.isEmpty)
            #expect(!help.lookFor.isEmpty)
        }
    }
}
