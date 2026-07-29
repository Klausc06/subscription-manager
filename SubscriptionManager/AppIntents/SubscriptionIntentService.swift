import Foundation
import SubscriptionCore

final class SubscriptionIntentService: @unchecked Sendable {
    private let workspace: SubscriptionWorkspace

    init(workspace: SubscriptionWorkspace) {
        self.workspace = workspace
    }

    @MainActor
    func add(
        _ input: SubscriptionCreationInput
    ) -> SubscriptionCreationResult {
        workspace.createSubscription(input)
    }

    @MainActor
    func subscriptions() throws -> [Subscription] {
        try workspace.subscriptions()
    }

    @MainActor
    func upcomingRenewals(
        from: Date,
        through: Date
    ) throws -> [UpcomingTimelineItem] {
        try workspace.upcomingRenewals(from: from, through: through)
    }

    @MainActor
    func monthlyForecast(containing date: Date) async -> SpendingInsightsState {
        let calendar = Calendar.current
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
        let monthEnd = calendar.date(
            byAdding: DateComponents(month: 1, day: -1),
            to: monthStart
        ) ?? monthStart
        await workspace.refreshExchangeRates()
        workspace.loadInsights(
            mode: .expected,
            from: monthStart,
            through: monthEnd
        )
        return workspace.insightsState
    }
}
