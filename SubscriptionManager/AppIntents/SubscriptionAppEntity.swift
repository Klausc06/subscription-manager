import AppIntents
import Foundation
import SubscriptionCore

struct SubscriptionAppEntity: AppEntity, Identifiable {
    let id: String
    let serviceName: String
    let plan: String
    let category: String
    let isArchived: Bool

    init(subscription: Subscription) {
        id = subscription.id.uuidString
        serviceName = subscription.serviceName
        plan = subscription.plan
        category = subscription.category
        isArchived = subscription.isArchived
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation =
        "Subscription"
    static let defaultQuery = SubscriptionAppEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: serviceName),
            subtitle: LocalizedStringResource(
                stringLiteral: "\(plan) · \(category)"
            )
        )
    }
}

struct SubscriptionAppEntityQuery: EntityStringQuery {
    @Dependency private var service: SubscriptionIntentService

    func entities(
        for identifiers: [SubscriptionAppEntity.ID]
    ) async throws -> [SubscriptionAppEntity] {
        let subscriptions = try await service.subscriptions()
        return subscriptions
            .filter { identifiers.contains($0.id.uuidString) }
            .map(SubscriptionAppEntity.init)
    }

    func entities(
        matching string: String
    ) async throws -> [SubscriptionAppEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let subscriptions = try await service.subscriptions()
        return subscriptions
            .filter { subscription in
                query.isEmpty || [
                    subscription.serviceName,
                    subscription.plan,
                    subscription.category,
                ].contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
            }
            .map(SubscriptionAppEntity.init)
    }

    func suggestedEntities() async throws -> [SubscriptionAppEntity] {
        try await service.subscriptions()
            .filter { !$0.isArchived }
            .map(SubscriptionAppEntity.init)
    }
}
