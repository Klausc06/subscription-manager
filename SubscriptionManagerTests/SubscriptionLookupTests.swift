import Foundation
import SwiftData
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("Subscription lookup")
struct SubscriptionLookupTests {
    @Test("Looking up an identifier selects the matching subscription")
    @MainActor
    func lookupSelectsMatchingSubscriptionAmongMultipleRecords() throws {
        let first = makeSubscription(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            serviceName: "First service"
        )
        let expected = makeSubscription(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            serviceName: "Expected service"
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        try repository.createSubscription(first)
        try repository.createSubscription(expected)

        let result = try repository.subscription(id: expected.id)

        #expect(result == expected)
    }

    @Test("Deleting one identifier preserves unrelated subscriptions")
    @MainActor
    func deletingOneIdentifierPreservesUnrelatedSubscriptions() throws {
        let deleted = makeSubscription(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            serviceName: "Deleted service"
        )
        let preserved = makeSubscription(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            serviceName: "Preserved service"
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        try repository.createSubscription(deleted)
        try repository.createSubscription(preserved)

        try repository.deleteSubscription(id: deleted.id)

        #expect(try repository.subscription(id: deleted.id) == nil)
        #expect(try repository.subscription(id: preserved.id) == preserved)
        #expect(try repository.listSubscriptions() == [preserved])
    }

    private func makeSubscription(
        id: UUID,
        serviceName: String
    ) -> Subscription {
        Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(id.uuidString)"
            ),
            serviceName: serviceName,
            plan: "Monthly",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: Date(
                timeIntervalSince1970: 1_769_904_000
            ),
            managementURL: nil,
            notes: ""
        )
    }
}
