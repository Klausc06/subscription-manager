import SwiftData
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("SwiftData subscription repository")
struct SwiftDataSubscriptionRepositoryTests {
    @Test("A fresh in-memory store exposes an empty library")
    @MainActor
    func freshStoreIsEmpty() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )

        let subscriptions = try repository.listSubscriptions()

        #expect(subscriptions.isEmpty)
    }
}
