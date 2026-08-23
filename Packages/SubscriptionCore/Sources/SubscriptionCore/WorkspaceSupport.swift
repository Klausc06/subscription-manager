import Foundation
import Observation

extension SubscriptionWorkspace {
    public func makeWidgetSnapshot() -> WidgetSnapshot? {
        let hidesAmounts = currentPreferences.hideAmountsInCalendar
        do {
            let nextRenewal = try repository.listSubscriptions()
                .compactMap { subscription -> WidgetRenewalSnapshot? in
                    guard let charge = makePresentationNextExpectedCharge(
                        for: subscription
                    ) else {
                        return nil
                    }
                    return WidgetRenewalSnapshot(
                        subscriptionID: subscription.id,
                        serviceName: subscription.serviceName,
                        renewalDate: charge.scheduledDate,
                        amountDescription: hidesAmounts
                            ? nil : formattedWidgetAmount(charge.amount),
                        isRateStale: false
                    )
                }
                .min { lhs, rhs in
                    if lhs.renewalDate != rhs.renewalDate {
                        return lhs.renewalDate < rhs.renewalDate
                    }
                    return lhs.subscriptionID.uuidString < rhs.subscriptionID.uuidString
                }
            return WidgetSnapshot(generatedAt: now(), nextRenewal: nextRenewal)
        } catch {
            return nil
        }
    }
    func validate(
        _ input: SubscriptionCreationInput
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if let originalAmount = input.originalAmount {
            if originalAmount.minorUnits <= 0 {
                errors[.originalAmount] = .mustBePositive
            }
        } else {
            errors[.originalAmount] = .required
        }
        if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
            errors[.billingSchedule] = .required
        }
        if input.initialStatus == .trial {
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        }
        if !input.billingInterval.isValid {
            errors[.billingSchedule] = .mustBePositive
        } else if TimeZone(
            identifier: input.billingTimeZoneIdentifier
        ) == nil {
            errors[.billingSchedule] = .required
        }

        return errors
    }
    func validate(
        _ input: SubscriptionEditInput,
        lifecycle: SubscriptionLifecycle
    ) -> [SubscriptionCreationField: SubscriptionCreationValidationError] {
        var errors:
            [SubscriptionCreationField: SubscriptionCreationValidationError]
            = [:]
        let whitespace = CharacterSet.whitespacesAndNewlines

        if input.serviceName.trimmingCharacters(in: whitespace).isEmpty {
            errors[.serviceName] = .required
        }
        if input.amount.minorUnits <= 0 {
            errors[.originalAmount] = .mustBePositive
        }
        switch lifecycle {
        case .active:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
                errors[.billingSchedule] = .required
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            }
        case .trial:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite {
                errors[.billingSchedule] = .required
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        case .cancelled:
            if !input.startDate.timeIntervalSinceReferenceDate.isFinite
                || !input.billingSchedule.renewalAnchor
                    .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.billingSchedule] = .required
            } else if input.billingSchedule.renewalAnchor < input.startDate {
                errors[.renewalAnchor] = .beforeStartDate
            }
            if !input.confirmedNextRenewal
                .timeIntervalSinceReferenceDate.isFinite
            {
                errors[.confirmedNextRenewal] = .required
            } else if input.confirmedNextRenewal < input.startDate {
                errors[.confirmedNextRenewal] = .beforeStartDate
            }
        }
        if !input.billingSchedule.interval.isValid {
            errors[.billingSchedule] = .mustBePositive
        } else if TimeZone(
            identifier: input.billingSchedule.timeZoneIdentifier
        ) == nil {
            errors[.billingSchedule] = .required
        }

        return errors
    }
    func editedPriceChanges(
        for existing: Subscription,
        amount: Money,
        confirmedNextRenewal: Date,
        calendar: Calendar
    ) -> [PriceChange] {
        let currentAmount = existing.amount(
            onBillingDay: confirmedNextRenewal
        )
        guard amount != currentAmount else {
            return existing.priceChanges
        }

        let sameDayWinnerIndex = existing.priceChanges.indices
            .filter {
                calendar.isDate(
                    existing.priceChanges[$0].effectiveDate,
                    inSameDayAs: confirmedNextRenewal
                )
            }
            .max {
                existing.priceChanges[$0].id.uuidString
                    < existing.priceChanges[$1].id.uuidString
            }

        if let index = sameDayWinnerIndex {
            var corrected = existing.priceChanges
            let existingChange = corrected[index]
            corrected[index] = PriceChange(
                id: existingChange.id,
                effectiveDate: confirmedNextRenewal,
                amount: amount
            )
            return corrected
        }

        return existing.priceChanges + [
            PriceChange(
                id: identifierGenerator(),
                effectiveDate: confirmedNextRenewal,
                amount: amount
            ),
        ]
    }
    func billingTimeZone(
        for subscription: Subscription
    ) -> TimeZone {
        TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? calendar.timeZone
    }
    func publishWidgetSnapshot() {
        guard let snapshot = makeWidgetSnapshot() else { return }
        widgetSnapshotPublisher?.publish(snapshot)
    }
    func formattedWidgetAmount(_ money: Money) -> String {
        (Decimal(money.minorUnits) / 100).formatted(
            .currency(code: money.currency.rawValue).locale(.current)
        )
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
    func expectedCharge(
        for subscription: Subscription,
        scheduledDate: Date,
        calendar: Calendar
    ) -> ExpectedCharge {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: scheduledDate
        )
        let id = ScheduledChargeID(
            subscriptionID: subscription.id,
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
        let amount = subscription.amount(onBillingDay: scheduledDate)
        return ExpectedCharge(
            id: id,
            subscriptionID: subscription.id,
            scheduledDate: scheduledDate,
            amount: amount
        )
    }
    func isScheduledOccurrence(
        _ date: Date,
        for subscription: Subscription,
        calendar: Calendar
    ) -> Bool {
        guard date >= subscription.startDate else {
            return false
        }
        let firstCandidateIndex = estimatedOccurrenceIndex(
            for: subscription.billingSchedule,
            onOrAfter: date,
            calendar: calendar
        )
        // The estimate is deliberately conservative so forecasting can find
        // the first occurrence on or after a boundary. Check that candidate
        // and the immediately following one when validating a user-selected
        // past occurrence.
        for occurrenceIndex in firstCandidateIndex...(firstCandidateIndex + 1) {
            guard let occurrence = scheduledDate(
                for: subscription.billingSchedule,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            ) else {
                continue
            }
            if calendar.isDate(occurrence, inSameDayAs: date) {
                return true
            }
        }
        return false
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
