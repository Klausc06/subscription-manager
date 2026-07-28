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

    @Test("A subscription derives its first expected charge from source fields")
    func subscriptionDerivesFirstExpectedCharge() {
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

        #expect(
            subscription.firstExpectedCharge == ExpectedCharge(
                subscriptionID: id,
                scheduledDate: renewalDate,
                amount: amount
            )
        )
        #expect(
            subscription.lifecycle
                == .trial(firstPaidChargeAt: subscription.confirmedNextRenewal)
        )
        #expect(subscription.isArchived == false)
    }
}
