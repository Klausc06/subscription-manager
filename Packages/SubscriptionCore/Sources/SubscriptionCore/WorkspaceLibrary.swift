import Foundation
import Observation

extension SubscriptionWorkspace {
    public func loadLibrary(
        scope: SubscriptionLibraryScope = .current
    ) {
        libraryState = .loading(scope)
        do {
            libraryState = try makeLibraryState(scope: scope)
            publishWidgetSnapshot()
        } catch {
            libraryState = .failed(scope)
        }
    }
    public func reloadLibrary() {
        loadLibrary(scope: carriedLibraryScope)
    }
    public func reloadAfterRemoteImport() async {
        let scope = carriedLibraryScope
        loadLibrary(scope: scope)
        reloadPreferencesAfterRemoteImport()
        if insightsRequest != nil {
            await refreshExchangeRates()
        }
        reloadRequestedConsumers()
    }
    func reloadPreferencesAfterRemoteImport() {
        guard preferencesRepository != nil else { return }
        let previousState = setupState
        loadSetup(
            libraryIsEmptyWhenPreferencesAreMissing:
                libraryIsEmptyAfterRemoteImport
        )
        if setupState != previousState {
            setupRevision &+= 1
        }
    }
    public func beginEditing() {
        editingValidationErrors = [:]
    }
    public func loadSubscription(id: UUID) {
        do {
            if let subscription = try repository.subscription(id: id) {
                detailState = makeDetail(subscription)
            } else {
                detailState = .notFound
                paymentHistory = []
            }
        } catch {
            detailState = .failed
            paymentHistory = []
        }
    }
    public func subscriptions() throws -> [Subscription] {
        try repository.listSubscriptions()
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
    public func subscription(for id: UUID) throws -> Subscription? {
        try repository.subscription(id: id)
    }
}
