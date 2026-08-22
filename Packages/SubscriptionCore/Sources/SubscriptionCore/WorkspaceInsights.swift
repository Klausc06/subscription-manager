import Foundation
import Observation

extension SubscriptionWorkspace {
    public func loadInsights(
        mode: SpendingReportMode,
        from: Date,
        through: Date
    ) {
        insightsRequest = InsightsRequest(mode: mode, from: from, through: through)
        guard from <= through,
              let snapshot = currentExchangeRateSnapshot
        else {
            insightsState = .unavailable
            return
        }

        let displayCurrency = currentPreferences.primaryCurrency
        do {
            let subscriptions = try repository.listSubscriptions()
            let rawItems = subscriptions.flatMap { subscription in
                makeSpendingInsightItems(
                    for: subscription,
                    mode: mode,
                    from: from,
                    through: through
                )
            }
            let items = try rawItems.map { item in
                SpendingInsightItem(
                    id: item.id,
                    subscriptionID: item.subscriptionID,
                    serviceName: item.serviceName,
                    category: item.category,
                    date: item.date,
                    originalAmount: item.amount,
                    convertedAmount: try snapshot.convert(
                        item.amount,
                        to: displayCurrency
                    )
                )
            }
            let sortedItems = items.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
            insightsState = .available(
                makeInsights(
                    mode: mode,
                    displayCurrency: displayCurrency,
                    from: from,
                    through: through,
                    items: sortedItems
                )
            )
        } catch {
            insightsState = .unavailable
        }
    }
    func reloadInsightsIfNeeded() {
        guard let insightsRequest else { return }
        loadInsights(
            mode: insightsRequest.mode,
            from: insightsRequest.from,
            through: insightsRequest.through
        )
    }
    func makeInsights(
        mode: SpendingReportMode,
        displayCurrency: Currency,
        from: Date,
        through: Date,
        items: [SpendingInsightItem]
    ) -> SpendingInsights {
        let totalMinorUnits = items.reduce(Int64.zero) {
            $0 + $1.convertedAmount.minorUnits
        }
        let total = Money(
            minorUnits: totalMinorUnits,
            currency: displayCurrency
        )
        let monthTotals = Dictionary(grouping: items) { item in
            calendar.date(
                from: calendar.dateComponents([.year, .month], from: item.date)
            ) ?? item.date
        }
        .map { month, items in
            SpendingMonthlyTotal(
                month: month,
                amount: Money(
                    minorUnits: items.reduce(Int64.zero) {
                        $0 + $1.convertedAmount.minorUnits
                    },
                    currency: displayCurrency
                )
            )
        }
        .sorted { $0.month < $1.month }
        let categoryTotals = Dictionary(grouping: items, by: \.category)
            .map { category, items in
                SpendingCategoryTotal(
                    category: category,
                    amount: Money(
                        minorUnits: items.reduce(Int64.zero) {
                            $0 + $1.convertedAmount.minorUnits
                        },
                        currency: displayCurrency
                    )
                )
            }
            .sorted { $0.category.localizedCompare($1.category) == .orderedAscending }
        let dayCount = max(
            1,
            (calendar.dateComponents([.day], from: from, to: through).day ?? 0)
                + 1
        )
        let annualizedMinorUnits = NSDecimalNumber(
            decimal: Decimal(totalMinorUnits) / Decimal(dayCount) * 365
        ).int64Value
        return SpendingInsights(
            mode: mode,
            displayCurrency: displayCurrency,
            selectedRangeTotal: total,
            annualizedTotal: Money(
                minorUnits: annualizedMinorUnits,
                currency: displayCurrency
            ),
            monthlyTotals: monthTotals,
            categoryTotals: categoryTotals,
            items: items
        )
    }
    func makeSpendingInsightItems(
        for subscription: Subscription,
        mode: SpendingReportMode,
        from: Date,
        through: Date
    ) -> [RawSpendingInsightItem] {
        guard !subscription.isArchived else { return [] }
        switch mode {
        case .expected:
            guard isEligibleForExpectedCharges(subscription) else { return [] }
            return makeExpectedCharges(
                for: subscription,
                from: from,
                through: through,
                maximumCount: .max
            )
            .filter { $0.scheduledDate >= from }
            .map { charge in
                RawSpendingInsightItem(
                    id: "expected:\(charge.id.subscriptionID.uuidString)-"
                        + "\(charge.id.year)-\(charge.id.month)-\(charge.id.day)",
                    subscriptionID: subscription.id,
                    serviceName: subscription.serviceName,
                    category: subscription.category,
                    date: charge.scheduledDate,
                    amount: charge.amount
                )
            }
        case .confirmed:
            return subscription.confirmedCharges
                .filter { $0.chargedDate >= from && $0.chargedDate <= through }
                .map { charge in
                    RawSpendingInsightItem(
                        id: "confirmed:\(charge.id.uuidString)",
                        subscriptionID: subscription.id,
                        serviceName: subscription.serviceName,
                        category: subscription.category,
                        date: charge.chargedDate,
                        amount: charge.amount
                    )
                }
        }
    }
}
