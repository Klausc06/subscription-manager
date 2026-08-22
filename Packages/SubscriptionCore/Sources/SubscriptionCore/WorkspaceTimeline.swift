import Foundation
import Observation

extension SubscriptionWorkspace {
    public func loadExpectedCharges(
        subscriptionID: UUID,
        through horizon: Date,
        maximumCount: Int = .max
    ) {
        expectedChargesRequest = ExpectedChargesRequest(
            subscriptionID: subscriptionID,
            horizon: horizon,
            maximumCount: maximumCount
        )
        do {
            guard let subscription = try repository.subscription(
                id: subscriptionID
            ) else {
                expectedCharges = nil
                return
            }
            expectedCharges = makeExpectedCharges(
                for: subscription,
                through: horizon,
                maximumCount: maximumCount
            )
        } catch {
            expectedCharges = nil
        }
    }
    public func loadUpcomingTimeline(from: Date, through: Date) {
        upcomingTimelineRequest = UpcomingTimelineRequest(
            from: from,
            through: through
        )
        do {
            let timeline = try upcomingRenewals(from: from, through: through)
            upcomingTimeline = timeline
            upcomingTimelineState = timeline.isEmpty ? .empty : .loaded(timeline)
        } catch {
            upcomingTimeline = []
            upcomingTimelineState = .failed
        }
    }
    public func upcomingRenewals(
        from: Date,
        through: Date
    ) throws -> [UpcomingTimelineItem] {
        guard from <= through else { return [] }
        return try subscriptions()
            .flatMap { subscription in
                makeUpcomingTimelineItems(
                    for: subscription,
                    from: from,
                    through: through
                )
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
    }
    func makeUpcomingTimelineItems(
        for subscription: Subscription,
        from: Date,
        through: Date
    ) -> [UpcomingTimelineItem] {
        guard !subscription.isArchived,
              isEligibleForExpectedCharges(subscription)
        else {
            return []
        }

        let expectedItems = makeExpectedCharges(
            for: subscription,
            from: from,
            through: through,
            maximumCount: .max
        )
        .map { charge in
            UpcomingTimelineItem(
                id: "expected:\(charge.id.subscriptionID.uuidString)-"
                    + "\(charge.id.year)-\(charge.id.month)-\(charge.id.day)",
                kind: .expected,
                subscriptionID: subscription.id,
                serviceName: subscription.serviceName,
                date: charge.scheduledDate,
                amount: charge.amount
            )
        }
        let confirmedItems = subscription.confirmedCharges
            .filter { $0.chargedDate >= from && $0.chargedDate <= through }
            .map { charge in
                UpcomingTimelineItem(
                    id: "confirmed:\(charge.id.uuidString)",
                    kind: .confirmed,
                    subscriptionID: subscription.id,
                    serviceName: subscription.serviceName,
                    date: charge.chargedDate,
                    amount: charge.amount
                )
            }
        return expectedItems + confirmedItems
    }
    func makePresentation(
        for subscription: Subscription
    ) -> (
        subscription: Subscription,
        status: SubscriptionStatus,
        nextExpectedCharge: ExpectedCharge?
    ) {
        let timeZone = TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? calendar.timeZone
        let status = subscription.lifecycle.status(
            asOf: now(),
            timeZone: timeZone
        )
        let nextExpectedCharge = makePresentationNextExpectedCharge(
            for: subscription
        )
        let presentedSubscription =
            if case .active = subscription.lifecycle,
               let nextExpectedCharge
            {
                subscription.replacingLifecycleFacts(
                    confirmedNextRenewal:
                        nextExpectedCharge.scheduledDate
                )
            } else {
                subscription
            }
        return (
            presentedSubscription,
            status,
            nextExpectedCharge
        )
    }
    func makePresentationNextExpectedCharge(
        for subscription: Subscription
    ) -> ExpectedCharge? {
        guard isEligibleForExpectedCharges(subscription),
              let timeZone = TimeZone(
                  identifier:
                      subscription.billingSchedule.timeZoneIdentifier
              )
        else {
            return nil
        }
        guard case .active = subscription.lifecycle else {
            return makeExpectedCharges(
                for: subscription,
                through: .distantFuture,
                maximumCount: 1
            ).first
        }

        let resolver = BillingDateResolver()
        var renewal = resolver.nextRenewal(
            afterStart: subscription.billingSchedule.renewalAnchor,
            interval: subscription.billingSchedule.interval,
            asOf: now(),
            timeZone: timeZone
        )
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        for _ in 0 ... subscription.confirmedCharges.count {
            guard let scheduledDate = renewal else { return nil }
            let charge = expectedCharge(
                for: subscription,
                scheduledDate: scheduledDate,
                calendar: localCalendar
            )
            if !subscription.confirmedCharges.contains(where: {
                $0.sourceScheduledChargeID == charge.id
            }) {
                return charge
            }
            renewal = resolver.nextRenewal(
                afterStart: scheduledDate,
                interval: subscription.billingSchedule.interval,
                asOf: scheduledDate,
                timeZone: timeZone
            )
        }
        return nil
    }
}
