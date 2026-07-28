import Foundation
import SubscriptionCore
import Testing

@Suite("User preferences")
struct UserPreferencesTests {
    @Test("Preferences start with useful local defaults")
    func preferencesStartWithUsefulDefaults() {
        #expect(UserPreferences.default.primaryCurrency == .cny)
        #expect(
            UserPreferences.default.calendarProjectionHorizon == .twelveMonths
        )
        #expect(UserPreferences.default.setupStatus == .notCompleted)
    }

    @Test("An empty library starts setup and skipping persists the choice")
    @MainActor
    func emptyLibraryStartsSetupAndSkipPersists() throws {
        let preferences = InMemoryUserPreferencesRepository()
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository(),
            preferencesRepository: preferences
        )

        workspace.loadSetup(libraryIsEmpty: true)

        #expect(workspace.setupState == .needsSetup(.default))

        workspace.skipSetup()

        #expect(
            workspace.setupState == .skipped(
                UserPreferences(
                    primaryCurrency: .cny,
                    calendarProjectionHorizon: .twelveMonths,
                    setupStatus: .skipped
                )
            )
        )
        #expect(try preferences.loadPreferences()?.setupStatus == .skipped)
    }
}

@MainActor
private final class InMemoryUserPreferencesRepository: UserPreferencesRepository {
    private var preferences: UserPreferences?

    func loadPreferences() throws -> UserPreferences? { preferences }

    func savePreferences(_ preferences: UserPreferences) throws {
        self.preferences = preferences
    }
}

@MainActor
private struct EmptySubscriptionRepository: SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws {}
    func updateSubscription(_ subscription: Subscription) throws {}
    func deleteSubscription(id: UUID) throws {}
    func listSubscriptions() throws -> [Subscription] { [] }
    func subscription(id: UUID) throws -> Subscription? { nil }
}
