import Foundation
import SwiftData
import SubscriptionCore
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

    @Test("Preferences survive a SwiftData repository reload")
    @MainActor
    func preferencesRoundTripThroughSwiftData() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let expected = UserPreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths,
            setupStatus: .completed
        )

        try SwiftDataUserPreferencesRepository(modelContainer: container)
            .savePreferences(expected)

        let reloaded = try SwiftDataUserPreferencesRepository(
            modelContainer: container
        ).loadPreferences()

        #expect(reloaded == expected)
    }
}
