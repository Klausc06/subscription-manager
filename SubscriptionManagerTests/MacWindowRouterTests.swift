import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct MacWindowRouterTests {
    @Test("Setup presentation policy distinguishes incomplete and completed setup failures")
    func setupPresentationPolicyDistinguishesFailureStates() {
        let preferences = UserPreferences.default
        let completedPreferences = UserPreferences(
            primaryCurrency: .cny,
            calendarProjectionHorizon: .twelveMonths,
            setupStatus: .completed
        )
        let skippedPreferences = UserPreferences(
            primaryCurrency: .cny,
            calendarProjectionHorizon: .twelveMonths,
            setupStatus: .skipped
        )

        #expect(
            SetupSheetPresentation.shouldPresent(
                for: .needsSetup(preferences),
                permitsSetupPresentation: true
            )
        )
        #expect(
            !SetupSheetPresentation.shouldPresent(
                for: .failed(completedPreferences),
                permitsSetupPresentation: true
            )
        )
        #expect(
            !SetupSheetPresentation.shouldPresent(
                for: .failed(skippedPreferences),
                permitsSetupPresentation: true
            )
        )
        #expect(
            SetupSheetPresentation.shouldPresent(
                for: .failed(preferences),
                permitsSetupPresentation: true
            )
        )
        #expect(
            !SetupSheetPresentation.shouldPresent(
                for: .configurationSaveFailed(completedPreferences),
                permitsSetupPresentation: true
            )
        )
        #expect(
            !SetupSheetPresentation.shouldPresent(
                for: .needsSetup(preferences),
                permitsSetupPresentation: false
            )
        )
    }

    @Test("A shared setup write invalidates a stale second window")
    func setupInteractionRevisionInvalidatesStaleWindow() {
        let initialPreferences = UserPreferences.default
        let initialState = SetupState.needsSetup(initialPreferences)
        let firstWindowExpectedRevision: UInt64 = 0
        let secondWindowExpectedRevision: UInt64 = 0

        #expect(
            SetupSheetPresentation.isSetupInteractionActive(
                for: initialState,
                expectedSetupRevision: firstWindowExpectedRevision,
                currentSetupRevision: 0
            )
        )
        #expect(
            SetupSheetPresentation.isSetupInteractionActive(
                for: initialState,
                expectedSetupRevision: secondWindowExpectedRevision,
                currentSetupRevision: 0
            )
        )

        let updatedPreferences = UserPreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .twelveMonths,
            setupStatus: .notCompleted
        )
        let stateAfterFirstWindowWrite = SetupState.needsSetup(
            updatedPreferences
        )
        let sharedRevisionAfterFirstWindowWrite: UInt64 = 1

        #expect(
            SetupSheetPresentation.isSetupInteractionActive(
                for: stateAfterFirstWindowWrite,
                expectedSetupRevision: sharedRevisionAfterFirstWindowWrite,
                currentSetupRevision: sharedRevisionAfterFirstWindowWrite
            )
        )
        #expect(
            !SetupSheetPresentation.isSetupInteractionActive(
                for: stateAfterFirstWindowWrite,
                expectedSetupRevision: secondWindowExpectedRevision,
                currentSetupRevision: sharedRevisionAfterFirstWindowWrite
            )
        )

        let completedPreferences = UserPreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .twelveMonths,
            setupStatus: .completed
        )
        #expect(
            !SetupSheetPresentation.shouldPresent(
                for: .completed(completedPreferences),
                permitsSetupPresentation: true
            )
        )
        #expect(
            !SetupSheetPresentation.isSetupInteractionActive(
                for: .completed(completedPreferences),
                expectedSetupRevision: sharedRevisionAfterFirstWindowWrite,
                currentSetupRevision: sharedRevisionAfterFirstWindowWrite
            )
        )
    }

    #if os(macOS)
    @Test("A Mac command only matches its focused window")
    func commandTargetsOnlyFocusedWindow() {
        let focusedWindow = UUID()
        let otherWindow = UUID()

        #expect(
            MacWindowCommandTarget.matches(
                notificationObject: focusedWindow,
                targetID: focusedWindow
            )
        )
        #expect(
            !MacWindowCommandTarget.matches(
                notificationObject: focusedWindow,
                targetID: otherWindow
            )
        )
        #expect(
            !MacWindowCommandTarget.matches(
                notificationObject: nil,
                targetID: focusedWindow
            )
        )
    }
    #endif

    @Test("Quick Add remains pending until the recreated window consumes it")
    @MainActor
    func quickAddRouteIsRetainedUntilConsumed() {
        let router = MacWindowRouter()

        router.showQuickAdd()

        #expect(router.destination == .quickAdd)
        #expect(router.takeDestination() == .quickAdd)
        #expect(router.destination == .none)
    }

    @Test(
        "Every Mac add trigger presents the shared add flow",
        arguments: MacAddSubscriptionTrigger.allCases
    )
    func everyAddTriggerPresentsCatalog(
        trigger: MacAddSubscriptionTrigger
    ) {
        var presentation = MacAddPresentationState()

        presentation.present(from: trigger, scope: .current)

        #expect(presentation.isPresented)
        #expect(presentation.trigger == trigger)
        #expect(presentation.scope == .current)
    }

    @Test("Archived add completion reloads the archived library scope")
    func archivedAddCompletionReloadsArchivedScope() {
        var presentation = MacAddPresentationState()
        var reloadedScope: SubscriptionLibraryScope?
        presentation.present(from: .toolbar, scope: .archived)

        presentation.complete { scope in
            reloadedScope = scope
        }

        #expect(reloadedScope == .archived)
    }
}
