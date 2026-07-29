import Testing
@testable import SubscriptionManager

struct MacWindowRouterTests {
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

        presentation.present(from: trigger)

        #expect(presentation.isPresented)
        #expect(presentation.trigger == trigger)
    }
}
