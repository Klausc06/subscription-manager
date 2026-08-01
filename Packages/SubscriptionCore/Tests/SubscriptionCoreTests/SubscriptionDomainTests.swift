import SubscriptionCore
import Foundation
import Testing

@Suite("Subscription domain values")
struct SubscriptionDomainTests {
    @Test("CNY money preserves exact minor units")
    func cnyMoneyPreservesExactMinorUnits() {
        let money = Money(minorUnits: 1_999, currency: .cny)

        #expect(money.minorUnits == 1_999)
        #expect(money.currency == .cny)
    }

    @Test("USD money preserves exact cents without floating point input")
    func usdMoneyPreservesExactCents() {
        let money = Money(minorUnits: 1_001, currency: .usd)

        #expect(money == Money(minorUnits: 1_001, currency: .usd))
    }

    @Test("The default supported billing interval is monthly")
    func defaultSupportedBillingIntervalIsMonthly() {
        #expect(BillingInterval.monthly.rawValue == "monthly")
    }

    @Test("A subscription preserves its renewal gate and lifecycle facts")
    func subscriptionPreservesRenewalGateAndLifecycleFacts() {
        let id = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
        let amount = Money(minorUnits: 2_345, currency: .usd)
        let subscription = Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(rawValue: "manual:\(id.uuidString)"),
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: amount,
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: renewalDate,
            managementURL: nil,
            notes: "",
            lifecycle: .trial(firstPaidChargeAt: renewalDate)
        )

        #expect(subscription.confirmedNextRenewal == renewalDate)
        #expect(
            subscription.lifecycle
                == .trial(firstPaidChargeAt: subscription.confirmedNextRenewal)
        )
        #expect(subscription.isArchived == false)
    }

    @Test("Confirmed charges retain their scheduled occurrence identity")
    func confirmedChargesRetainScheduledOccurrenceIdentity() {
        let subscriptionID = UUID(
            uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )!
        let source = ScheduledChargeID(
            subscriptionID: subscriptionID,
            year: 2026,
            month: 7,
            day: 29
        )
        let confirmedCharge = ConfirmedCharge(
            id: UUID(),
            chargedDate: Date(timeIntervalSince1970: 1_785_326_400),
            amount: Money(minorUnits: 1_299, currency: .usd),
            sourceScheduledChargeID: source
        )

        #expect(confirmedCharge.sourceScheduledChargeID == source)
    }

    @Test("Price changes preserve their effective money")
    func priceChangesPreserveEffectiveMoney() {
        let amount = Money(minorUnits: 1_499, currency: .usd)
        let priceChange = PriceChange(
            id: UUID(),
            effectiveDate: Date(timeIntervalSince1970: 1_785_326_400),
            amount: amount
        )

        #expect(priceChange.amount == amount)
    }

    @Test("Effective amount follows billing-local price history")
    func effectiveAmountFollowsBillingLocalHistory() throws {
        let calendar = utcCalendar()
        let start = try actionDate(
            year: 2026, month: 1, day: 10, hour: 12, calendar: calendar
        )
        let firstChange = try actionDate(
            year: 2026, month: 2, day: 10, hour: 12, calendar: calendar
        )
        let secondChange = try actionDate(
            year: 2026, month: 3, day: 10, hour: 12, calendar: calendar
        )
        let subscription = makeSubscription(
            originalAmount: Money(minorUnits: 999, currency: .usd),
            startDate: start,
            priceChanges: [
                PriceChange(
                    id: UUID(
                        uuidString: "10000000-0000-0000-0000-000000000002"
                    )!,
                    effectiveDate: secondChange,
                    amount: Money(minorUnits: 6_800, currency: .cny)
                ),
                PriceChange(
                    id: UUID(
                        uuidString: "10000000-0000-0000-0000-000000000001"
                    )!,
                    effectiveDate: firstChange,
                    amount: Money(minorUnits: 1_499, currency: .usd)
                ),
            ]
        )

        #expect(subscription.amount(onBillingDay: start) == Money(
            minorUnits: 999, currency: .usd
        ))
        #expect(subscription.amount(onBillingDay: firstChange) == Money(
            minorUnits: 1_499, currency: .usd
        ))
        #expect(subscription.amount(onBillingDay: secondChange) == Money(
            minorUnits: 6_800, currency: .cny
        ))
    }

    @Test("Effective amount breaks same billing-local day ties by UUID")
    func effectiveAmountUsesUUIDForSameBillingLocalDay() throws {
        let utc = utcCalendar()
        let start = try actionDate(
            year: 2026, month: 1, day: 10, hour: 12, calendar: utc
        )
        let firstChange = try actionDate(
            year: 2026, month: 2, day: 10, hour: 8, calendar: utc
        )
        let secondChange = try actionDate(
            year: 2026, month: 2, day: 11, hour: 7, calendar: utc
        )
        let billingDay = try actionDate(
            year: 2026, month: 2, day: 11, hour: 12, calendar: utc
        )
        let schedule = FixedBillingSchedule(
            interval: .monthly,
            renewalAnchor: start,
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let subscription = Subscription(
            id: UUID(),
            serviceIdentity: ServiceIdentity(rawValue: "manual:test"),
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: schedule,
            startDate: start,
            confirmedNextRenewal: billingDay,
            managementURL: nil,
            notes: "",
            priceChanges: [
                PriceChange(
                    id: UUID(
                        uuidString: "20000000-0000-0000-0000-000000000002"
                    )!,
                    effectiveDate: secondChange,
                    amount: Money(minorUnits: 2_002, currency: .usd)
                ),
                PriceChange(
                    id: UUID(
                        uuidString: "20000000-0000-0000-0000-000000000001"
                    )!,
                    effectiveDate: firstChange,
                    amount: Money(minorUnits: 2_001, currency: .usd)
                ),
            ]
        )

        #expect(subscription.amount(onBillingDay: billingDay) == Money(
            minorUnits: 2_002, currency: .usd
        ))
    }

    @Test("Effective amount falls back to GMT for an invalid billing time zone")
    func effectiveAmountFallsBackToGMTForInvalidTimeZone() throws {
        let calendar = utcCalendar()
        let start = try actionDate(
            year: 2026, month: 1, day: 10, hour: 12, calendar: calendar
        )
        let effectiveDate = try actionDate(
            year: 2026, month: 2, day: 10, hour: 23, calendar: calendar
        )
        let billingDay = try actionDate(
            year: 2026, month: 2, day: 11, hour: 1, calendar: calendar
        )
        let schedule = FixedBillingSchedule(
            interval: .monthly,
            renewalAnchor: start,
            timeZoneIdentifier: "Invalid/TimeZone"
        )
        let subscription = Subscription(
            id: UUID(),
            serviceIdentity: ServiceIdentity(rawValue: "manual:test"),
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: schedule,
            startDate: start,
            confirmedNextRenewal: billingDay,
            managementURL: nil,
            notes: "",
            priceChanges: [
                PriceChange(
                    id: UUID(),
                    effectiveDate: effectiveDate,
                    amount: Money(minorUnits: 1_499, currency: .usd)
                ),
            ]
        )

        #expect(subscription.amount(onBillingDay: billingDay) == Money(
            minorUnits: 1_499, currency: .usd
        ))
    }

    @Test("Legacy subscription summaries decode without an effective amount")
    func legacySubscriptionSummaryDecodesWithoutAmount() throws {
        let start = try actionDate(
            year: 2026,
            month: 1,
            day: 10,
            hour: 12,
            calendar: utcCalendar()
        )
        let subscription = makeSubscription(
            originalAmount: Money(minorUnits: 999, currency: .usd),
            startDate: start,
            priceChanges: []
        )
        let summary = SubscriptionSummary(
            subscription: subscription,
            status: .active,
            nextExpectedCharge: nil
        )
        let encoded = try JSONEncoder().encode(summary)
        let current = try JSONDecoder().decode(
            SubscriptionSummary.self,
            from: encoded
        )
        #expect(current == summary)

        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject["amount"] = nil
        let legacyData = try JSONSerialization.data(
            withJSONObject: legacyObject
        )
        let legacy = try JSONDecoder().decode(
            SubscriptionSummary.self,
            from: legacyData
        )
        #expect(legacy.originalAmount == summary.originalAmount)
        #expect(legacy.amount == summary.originalAmount)
    }

    private func makeSubscription(
        originalAmount: Money,
        startDate: Date,
        priceChanges: [PriceChange]
    ) -> Subscription {
        let schedule = FixedBillingSchedule(
            interval: .monthly,
            renewalAnchor: startDate,
            timeZoneIdentifier: "UTC"
        )
        return Subscription(
            id: UUID(),
            serviceIdentity: ServiceIdentity(rawValue: "manual:test"),
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: originalAmount,
            billingSchedule: schedule,
            startDate: startDate,
            confirmedNextRenewal: startDate,
            managementURL: nil,
            notes: "",
            priceChanges: priceChanges
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func actionDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }
}
