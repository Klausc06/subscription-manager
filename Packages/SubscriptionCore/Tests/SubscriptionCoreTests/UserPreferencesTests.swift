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
        #expect(UserPreferences.default.hideAmountsInCalendar == false)
        #expect(UserPreferences.default.menuBarModeEnabled == false)
        #expect(UserPreferences.default.setupStatus == .notCompleted)
    }

    @Test("Legacy preferences decode with calendar amounts visible")
    func legacyPreferencesDefaultCalendarAmountVisibility() throws {
        let legacyData = Data(
            """
            {
              "primaryCurrency": "USD",
              "calendarProjectionHorizon": 6,
              "setupStatus": "completed"
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(
            UserPreferences.self,
            from: legacyData
        )

        #expect(preferences.hideAmountsInCalendar == false)
        #expect(preferences.menuBarModeEnabled == false)
    }

    @Test("Menu-bar mode persists through the workspace preference command")
    @MainActor
    func menuBarModePersistsThroughWorkspace() throws {
        let preferences = InMemoryUserPreferencesRepository()
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository(),
            preferencesRepository: preferences
        )

        workspace.loadSetup(libraryIsEmpty: false)
        workspace.updatePreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths,
            menuBarModeEnabled: true
        )

        #expect(
            try preferences.loadPreferences()?.menuBarModeEnabled == true
        )
        #expect(
            workspace.setupState == .needsSetup(
                UserPreferences(
                    primaryCurrency: .usd,
                    calendarProjectionHorizon: .sixMonths,
                    menuBarModeEnabled: true,
                    setupStatus: .notCompleted
                )
            )
        )
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

    @Test("Stored incomplete setup resumes even after a subscription was saved")
    @MainActor
    func storedIncompleteSetupResumesWithNonEmptyLibrary() throws {
        let preferences = InMemoryUserPreferencesRepository()
        try preferences.savePreferences(.default)
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository(),
            preferencesRepository: preferences
        )

        workspace.loadSetup(libraryIsEmpty: false)

        #expect(workspace.setupState == .needsSetup(.default))
    }

    @Test("A failed preference save keeps setup recoverable")
    @MainActor
    func failedPreferenceSaveKeepsSetupRecoverable() {
        let preferences = InMemoryUserPreferencesRepository()
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository(),
            preferencesRepository: preferences
        )
        workspace.loadSetup(libraryIsEmpty: true)
        preferences.shouldFailSaves = true

        workspace.skipSetup()

        #expect(workspace.setupState == .failed(.default))
    }
}

@MainActor
private final class InMemoryUserPreferencesRepository: UserPreferencesRepository {
    private var preferences: UserPreferences?
    var shouldFailSaves = false

    func loadPreferences() throws -> UserPreferences? { preferences }

    func savePreferences(_ preferences: UserPreferences) throws {
        if shouldFailSaves {
            throw InMemoryPreferencesError.saveFailed
        }
        self.preferences = preferences
    }
}

private enum InMemoryPreferencesError: Error {
    case saveFailed
}

@MainActor
private struct EmptySubscriptionRepository: SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws {}
    func updateSubscription(_ subscription: Subscription) throws {}
    func deleteSubscription(id: UUID) throws {}
    func listSubscriptions() throws -> [Subscription] { [] }
    func subscription(id: UUID) throws -> Subscription? { nil }
}
