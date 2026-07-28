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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
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
