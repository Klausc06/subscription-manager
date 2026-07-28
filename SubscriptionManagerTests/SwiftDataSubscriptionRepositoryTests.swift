import Foundation
import SwiftData
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("SwiftData subscription repository")
struct SwiftDataSubscriptionRepositoryTests {
    private enum StoreInitializationFailure: Error {
        case unavailable
    }

    @Test("A store initialization failure remains renderable")
    @MainActor
    func storeInitializationFailureIsRecoverable() {
        let startupState = AppDependencies.make {
            throw StoreInitializationFailure.unavailable
        }

        guard case .failed(let failure) = startupState else {
            Issue.record("Expected a recoverable startup failure")
            return
        }

        #expect(failure.underlyingError is StoreInitializationFailure)
    }

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

    @Test("A saved record keeps its stable identifier")
    @MainActor
    func savedRecordKeepsItsIdentifier() throws {
        let expectedID = UUID(
            uuidString: "6FD01C11-CE25-4987-9C6F-02B46F080D63"
        )!
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        container.mainContext.insert(SubscriptionRecord(id: expectedID))
        try container.mainContext.save()
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )

        let subscriptions = try repository.listSubscriptions()

        #expect(subscriptions.map(\.id) == [expectedID])
    }
}
