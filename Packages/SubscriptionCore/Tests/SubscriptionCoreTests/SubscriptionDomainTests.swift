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
}
