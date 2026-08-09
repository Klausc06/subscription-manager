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
        #expect(UserPreferences.default.appearanceMode == .system)
        #expect(UserPreferences.default.setupStatus == .notCompleted)
    }

    @Test("Appearance modes encode and decode without changing")
    func appearanceModesRoundTripThroughCodable() throws {
        for appearanceMode in AppearanceMode.allCases {
            let original = UserPreferences(
                primaryCurrency: .eur,
                calendarProjectionHorizon: .sixMonths,
                appearanceMode: appearanceMode,
                setupStatus: .completed
            )
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(
                UserPreferences.self,
                from: data
            )

            #expect(decoded == original)
        }
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
        #expect(preferences.appearanceMode == .system)
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

    @Test("A non-empty library persists completed setup when preferences are absent")
    @MainActor
    func nonEmptyLibraryPersistsCompletedSetupWithoutPreferences() throws {
        let preferences = InMemoryUserPreferencesRepository()
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository(),
            preferencesRepository: preferences
        )

        workspace.loadSetup(libraryIsEmpty: false)
        workspace.markExistingLibraryAsConfiguredIfNeeded(
            currentLibraryState: nonEmptyCurrentLibraryState,
            archivedLibraryState: .empty(.archived)
        )

        #expect(try preferences.loadPreferences()?.setupStatus == .completed)
    }

    @Test("An existing library stays out of first-run setup when automatic preference persistence fails")
    @MainActor
    func existingLibraryStaysUsableWhenAutomaticConfigurationSaveFails() throws {
        let preferences = InMemoryUserPreferencesRepository()
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository(),
            preferencesRepository: preferences
        )
        workspace.loadSetup(libraryIsEmpty: false)
        preferences.shouldFailSaves = true

        workspace.markExistingLibraryAsConfiguredIfNeeded(
            currentLibraryState: nonEmptyCurrentLibraryState,
            archivedLibraryState: .empty(.archived)
        )

        let completedPreferences = UserPreferences(
            primaryCurrency: .cny,
            calendarProjectionHorizon: .twelveMonths,
            setupStatus: .completed
        )
        #expect(
            workspace.setupState
                == .configurationSaveFailed(completedPreferences)
        )
        #expect(!workspace.setupState.requiresSetupInteraction)
        #expect(workspace.setupState.hasPreferenceSaveFailure)

        workspace.updatePreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths
        )

        #expect(
            workspace.setupState
                == .configurationSaveFailed(completedPreferences)
        )
        #expect(!workspace.setupState.requiresSetupInteraction)
        #expect(workspace.setupState.hasPreferenceSaveFailure)

        preferences.shouldFailSaves = false
        workspace.updatePreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths
        )

        let recoveredPreferences = UserPreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths,
            setupStatus: .completed
        )
        #expect(workspace.setupState == .completed(recoveredPreferences))
        #expect(try preferences.loadPreferences() == recoveredPreferences)
        #expect(!workspace.setupState.hasPreferenceSaveFailure)
    }

    @Test("Failed current and archived library loads do not complete setup")
    @MainActor
    func failedCurrentAndArchivedLibrariesDoNotCompleteSetup() throws {
        let preferences = InMemoryUserPreferencesRepository()
        let workspace = SubscriptionWorkspace(
            repository: SequencedSubscriptionRepository(
                responses: [.failure(.unavailable), .failure(.unavailable)]
            ),
            preferencesRepository: preferences
        )

        let states = initializeSetupLikeLibraryView(workspace)

        #expect(states.current == .failed(.current))
        #expect(states.archived == .failed(.archived))
        #expect(workspace.setupState == .loadFailed)
        #expect(try preferences.loadPreferences() == nil)
    }

    @Test("A failed library load beside an empty scope does not complete setup")
    @MainActor
    func failedLibraryBesideEmptyScopeDoesNotCompleteSetup() throws {
        let preferences = InMemoryUserPreferencesRepository()
        let workspace = SubscriptionWorkspace(
            repository: SequencedSubscriptionRepository(
                responses: [.failure(.unavailable), .success([]), .success([])]
            ),
            preferencesRepository: preferences
        )

        let states = initializeSetupLikeLibraryView(workspace)

        #expect(states.current == .failed(.current))
        #expect(states.archived == .empty(.archived))
        #expect(workspace.setupState == .loadFailed)
        #expect(try preferences.loadPreferences() == nil)

        _ = initializeSetupLikeLibraryView(workspace)

        #expect(workspace.setupState == .needsSetup(.default))
    }

    @Test("A failed preference read blocks setup until retry succeeds")
    @MainActor
    func failedPreferenceReadBlocksSetupUntilRetrySucceeds() {
        let preferences = InMemoryUserPreferencesRepository()
        preferences.shouldFailLoads = true
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository(),
            preferencesRepository: preferences
        )

        workspace.loadSetup(libraryIsEmpty: true)

        #expect(workspace.setupState == .loadFailed)

        preferences.shouldFailLoads = false
        workspace.loadSetup(libraryIsEmpty: true)

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

    @Test("Successful setup writes advance the shared revision")
    @MainActor
    func successfulSetupWritesAdvanceSharedRevision() {
        let preferences = InMemoryUserPreferencesRepository()
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository(),
            preferencesRepository: preferences
        )
        workspace.loadSetup(libraryIsEmpty: true)
        let initialRevision = workspace.setupRevision

        workspace.updatePreferences(
            primaryCurrency: .cny,
            calendarProjectionHorizon: .twelveMonths
        )

        #expect(workspace.setupRevision == initialRevision + 1)
        preferences.shouldFailSaves = true

        workspace.completeSetup()

        #expect(workspace.setupRevision == initialRevision + 1)
    }
}

@MainActor
private final class InMemoryUserPreferencesRepository: UserPreferencesRepository {
    private var preferences: UserPreferences?
    var shouldFailLoads = false
    var shouldFailSaves = false

    func loadPreferences() throws -> UserPreferences? {
        if shouldFailLoads {
            throw InMemoryPreferencesError.loadFailed
        }
        return preferences
    }

    func savePreferences(_ preferences: UserPreferences) throws {
        if shouldFailSaves {
            throw InMemoryPreferencesError.saveFailed
        }
        self.preferences = preferences
    }
}

private enum InMemoryPreferencesError: Error {
    case loadFailed
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

@MainActor
private final class SequencedSubscriptionRepository: SubscriptionRepository {
    private var responses: [Result<[Subscription], LibraryRepositoryError>]

    init(responses: [Result<[Subscription], LibraryRepositoryError>]) {
        self.responses = responses
    }

    func createSubscription(_ subscription: Subscription) throws {}
    func updateSubscription(_ subscription: Subscription) throws {}
    func deleteSubscription(id: UUID) throws {}

    func listSubscriptions() throws -> [Subscription] {
        let response = responses.isEmpty
            ? .success([])
            : responses.removeFirst()
        return try response.get()
    }

    func subscription(id: UUID) throws -> Subscription? { nil }
}

private enum LibraryRepositoryError: Error {
    case unavailable
}

@MainActor
private func initializeSetupLikeLibraryView(
    _ workspace: SubscriptionWorkspace
) -> (
    current: SubscriptionLibraryState,
    archived: SubscriptionLibraryState
) {
    workspace.loadLibrary(scope: .current)
    let currentState = workspace.libraryState
    workspace.loadLibrary(scope: .archived)
    let archivedState = workspace.libraryState
    workspace.loadLibrary(scope: .current)
    workspace.initializeSetup(
        currentLibraryState: currentState,
        archivedLibraryState: archivedState
    )
    return (currentState, archivedState)
}

private var nonEmptyCurrentLibraryState: SubscriptionLibraryState {
    let subscription = Subscription(
        id: UUID(),
        serviceIdentity: ServiceIdentity(rawValue: "test:existing"),
        serviceName: "Existing",
        plan: "Monthly",
        category: "Other",
        originalAmount: Money(minorUnits: 999, currency: .usd),
        billingCycle: .monthly,
        startDate: Date(timeIntervalSince1970: 0),
        confirmedNextRenewal: Date(timeIntervalSince1970: 0),
        managementURL: nil,
        notes: ""
    )
    return .loaded(
        .current,
        [SubscriptionSummary(
            subscription: subscription,
            status: .active,
            nextExpectedCharge: nil
        )]
    )
}
