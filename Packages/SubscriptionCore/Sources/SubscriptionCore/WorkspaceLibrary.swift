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
    func reloadRequestedConsumers() {
        if case .loaded(let subscription, _, _) = detailState {
            loadSubscription(id: subscription.id)
        }
        if let expectedChargesRequest {
            loadExpectedCharges(
                subscriptionID: expectedChargesRequest.subscriptionID,
                through: expectedChargesRequest.horizon,
                maximumCount: expectedChargesRequest.maximumCount
            )
        }
        if let upcomingTimelineRequest {
            loadUpcomingTimeline(
                from: upcomingTimelineRequest.from,
                through: upcomingTimelineRequest.through
            )
        }
        if let calendarProjectionLocale {
            loadCalendarProjection(locale: calendarProjectionLocale)
        }
        reloadInsightsIfNeeded()
    }
    func makeLibraryState(
        scope: SubscriptionLibraryScope
    ) throws -> SubscriptionLibraryState {
        let subscriptions = try repository.listSubscriptions()
            .filter { $0.isArchived == (scope == .archived) }
        let summaries = subscriptions.map(makeSummary)
        let orderedSummaries = scope == .current
            ? SubscriptionTableQuery().apply(to: summaries)
            : summaries
        return orderedSummaries.isEmpty
            ? .empty(scope)
            : .loaded(scope, orderedSummaries)
    }
    func makeSummary(
        _ subscription: Subscription
    ) -> SubscriptionSummary {
        let presentation = makePresentation(for: subscription)
        return SubscriptionSummary(
            subscription: presentation.subscription,
            status: presentation.status,
            nextExpectedCharge: presentation.nextExpectedCharge
        )
    }
    func makeDetail(
        _ subscription: Subscription
    ) -> SubscriptionDetailState {
        let presentation = makePresentation(for: subscription)
        paymentHistory = makeHistory(for: subscription)
        return .loaded(
            subscription: presentation.subscription,
            status: presentation.status,
            nextExpectedCharge: presentation.nextExpectedCharge
        )
    }
    func makeHistory(
        for subscription: Subscription
    ) -> [SubscriptionHistoryEntry] {
        let timeZone = billingTimeZone(for: subscription)
        let localCalendar = billingLocalCalendar(timeZone: timeZone)
        var entries: [SubscriptionHistoryEntry] =
            subscription.confirmedCharges.map(SubscriptionHistoryEntry.confirmed)
            + subscription.priceChanges.map(SubscriptionHistoryEntry.priceChange)

        if !subscription.isArchived,
           isEligibleForExpectedCharges(subscription)
        {
            let today = localCalendar.startOfDay(for: now())
            let candidateIndex = estimatedOccurrenceIndex(
                for: subscription.billingSchedule,
                onOrAfter: today,
                calendar: localCalendar
            )
            let startDay = localCalendar.startOfDay(for: subscription.startDate)
            let confirmedNextRenewalDay = localCalendar.startOfDay(
                for: subscription.confirmedNextRenewal
            )
            let missedOccurrence =
                HistoryOccurrenceSearch.firstUnconfirmedPastOccurrence(
                    candidateIndex: candidateIndex,
                    lowerBoundDay: max(startDay, confirmedNextRenewalDay),
                    todayDay: today,
                    occurrenceAt: { occurrenceIndex in
                        self.scheduledDate(
                            for: subscription.billingSchedule,
                            occurrenceIndex: occurrenceIndex,
                            calendar: localCalendar
                        )
                    },
                    day: localCalendar.startOfDay(for:),
                    isConfirmed: { occurrence in
                        let charge = self.expectedCharge(
                            for: subscription,
                            scheduledDate: occurrence,
                            calendar: localCalendar
                        )
                        return subscription.confirmedCharges.contains {
                            $0.sourceScheduledChargeID == charge.id
                        }
                    }
                )
            if let missedOccurrence {
                let missed = expectedCharge(
                    for: subscription,
                    scheduledDate: missedOccurrence,
                    calendar: localCalendar
                )
                entries.append(.expected(missed))
            }

            let tomorrow = localCalendar.date(
                byAdding: .day,
                value: 1,
                to: today
            ) ?? today
            let nextLowerBound = max(tomorrow, confirmedNextRenewalDay)
            let nextIndex = estimatedOccurrenceIndex(
                for: subscription.billingSchedule,
                onOrAfter: nextLowerBound,
                calendar: localCalendar
            )
            let next = (nextIndex...(nextIndex + 2)).compactMap {
                scheduledDate(
                    for: subscription.billingSchedule,
                    occurrenceIndex: $0,
                    calendar: localCalendar
                )
            }
            .filter { $0 >= nextLowerBound }
            .map {
                expectedCharge(
                    for: subscription,
                    scheduledDate: $0,
                    calendar: localCalendar
                )
            }
            .first { charge in
                !subscription.confirmedCharges.contains {
                    $0.sourceScheduledChargeID == charge.id
                }
            }
            if let next {
                entries.append(.expected(next))
            }
        }

        return entries.sorted { lhs, rhs in
            let left = historySortKey(lhs)
            let right = historySortKey(rhs)
            let leftDay = localCalendar.startOfDay(for: left.date)
            let rightDay = localCalendar.startOfDay(for: right.date)
            if leftDay != rightDay {
                return leftDay < rightDay
            }
            if left.kindOrder != right.kindOrder {
                return left.kindOrder < right.kindOrder
            }
            return left.date < right.date
        }
    }
    func historySortKey(
        _ entry: SubscriptionHistoryEntry
    ) -> (date: Date, kindOrder: Int) {
        switch entry {
        case .priceChange(let change):
            (change.effectiveDate, 0)
        case .expected(let charge):
            (charge.scheduledDate, 1)
        case .confirmed(let charge):
            (charge.chargedDate, 2)
        }
    }
    func isEligibleForExpectedCharges(
        _ subscription: Subscription
    ) -> Bool {
        guard !subscription.isArchived else {
            return false
        }
        if case .cancelled = subscription.lifecycle {
            return false
        }
        return true
    }
}
