import Foundation
import SwiftData
import SubscriptionCore

@MainActor
final class SwiftDataSubscriptionRepository: SubscriptionRepository {
    private let modelContext: ModelContext
    private let save: (ModelContext) throws -> Void

    convenience init(modelContainer: ModelContainer) {
        self.init(
            modelContainer: modelContainer,
            save: { try $0.save() }
        )
    }

    init(
        modelContainer: ModelContainer,
        save: @escaping (ModelContext) throws -> Void
    ) {
        modelContext = ModelContext(modelContainer)
        self.save = save
    }

    func createSubscription(_ subscription: Subscription) throws {
        modelContext.insert(
            SubscriptionRecord(
                id: subscription.id,
                serviceIdentityRawValue: subscription.serviceIdentity.rawValue,
                serviceName: subscription.serviceName,
                plan: subscription.plan,
                category: subscription.category,
                originalMinorUnits: subscription.originalAmount.minorUnits,
                currencyRawValue: subscription.originalAmount.currency.rawValue,
                billingCycleRawValue: subscription.billingCycle.rawValue,
                startDate: subscription.startDate,
                confirmedNextRenewal: subscription.confirmedNextRenewal,
                managementURLString: subscription.managementURL?.absoluteString,
                notes: subscription.notes
            )
        )
        do {
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func listSubscriptions() throws -> [SubscriptionSummary] {
        try modelContext
            .fetch(FetchDescriptor<SubscriptionRecord>())
            .map(makeSubscription(from:))
            .map(SubscriptionSummary.init(subscription:))
    }

    func subscription(id: UUID) throws -> Subscription? {
        try modelContext
            .fetch(FetchDescriptor<SubscriptionRecord>())
            .first { $0.id == id }
            .map(makeSubscription(from:))
    }

    private func makeSubscription(
        from record: SubscriptionRecord
    ) -> Subscription {
        let serviceIdentityRawValue = record.serviceIdentityRawValue.isEmpty
            ? "manual:\(record.id.uuidString)"
            : record.serviceIdentityRawValue
        let managementURL = record.managementURLString.flatMap { value in
            value.isEmpty ? nil : URL(string: value)
        }

        return Subscription(
            id: record.id,
            serviceIdentity: ServiceIdentity(
                rawValue: serviceIdentityRawValue
            ),
            serviceName: record.serviceName,
            plan: record.plan,
            category: record.category,
            originalAmount: Money(
                minorUnits: record.originalMinorUnits,
                currency: Currency(rawValue: record.currencyRawValue) ?? .usd
            ),
            billingCycle: BillingCycle(
                rawValue: record.billingCycleRawValue
            ) ?? .monthly,
            startDate: record.startDate,
            confirmedNextRenewal: record.confirmedNextRenewal,
            managementURL: managementURL,
            notes: record.notes ?? ""
        )
    }
}
