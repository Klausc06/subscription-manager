import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("Billing interval form values")
struct BillingScheduleSupportTests {
    @Test("Custom intervals preserve their value and unit")
    func customIntervalPreservesValueAndUnit() {
        let values = BillingIntervalFormValues(
            interval: .custom(value: 2, unit: .month)
        )

        #expect(values.choice == .custom)
        #expect(values.customValueText == "2")
        #expect(values.customUnit == .month)
    }

    @Test("Standard intervals clear stale custom values")
    func standardIntervalClearsCustomValues() {
        let values = BillingIntervalFormValues(interval: .monthly)

        #expect(values.choice == .monthly)
        #expect(values.customValueText.isEmpty)
        #expect(values.customUnit == .day)
    }
}
