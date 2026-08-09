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

    #if os(macOS)
    @Test("Add Subscription replaces the default New Window command")
    func addSubscriptionReplacesDefaultNewWindowCommand() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "SubscriptionManager/App/SubscriptionManagerApp.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("CommandGroup(replacing: .newItem)"))
        #expect(!source.contains("CommandGroup(after: .newItem)"))
    }

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
