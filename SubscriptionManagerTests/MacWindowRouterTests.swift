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
}
