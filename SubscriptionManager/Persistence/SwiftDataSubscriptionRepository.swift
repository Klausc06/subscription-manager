import SwiftData
import SubscriptionCore

@MainActor
final class SwiftDataSubscriptionRepository: SubscriptionRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func listSubscriptions() throws -> [SubscriptionSummary] {
        try modelContext
            .fetch(FetchDescriptor<SubscriptionRecord>())
            .map { SubscriptionSummary(id: $0.id) }
    }
}
