import Foundation
import Testing
@testable import SubscriptionManager

struct AppDependenciesTests {
    @Test("A named UI testing store is ignored outside UI testing")
    @MainActor
    func namedStoreRequiresUITestingMode() throws {
        let selection = try AppDependencies.storeSelection(
            arguments: [
                "SubscriptionManager",
                "--ui-testing-store",
                "must-not-select-a-test-store",
            ]
        )

        #expect(selection == .production)
    }

    @Test("UI testing can select a named persistent store")
    @MainActor
    func namedStoreIsAvailableInUITestingMode() throws {
        let selection = try AppDependencies.storeSelection(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                "relaunch-contract",
            ]
        )

        #expect(selection == .namedUITesting(token: "relaunch-contract"))
    }
}
