import Foundation
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
        #expect(
            values.choice.interval(
                customValueText: values.customValueText,
                customUnit: values.customUnit
            ) == .custom(value: 2, unit: .month)
        )
    }

    @Test("Standard intervals clear stale custom values")
    func standardIntervalClearsCustomValues() {
        let values = BillingIntervalFormValues(interval: .monthly)

        #expect(values.choice == .monthly)
        #expect(values.customValueText.isEmpty)
        #expect(values.customUnit == .day)
    }

    @Test("Editing Start Date finds the first renewal after today")
    func editingStartDateFindsUpcomingRenewal() throws {
        let editState = BillingDateEditState()
        let calendar = try #require(
            BillingCalendar.calendar(timeZoneIdentifier: "UTC")
        )
        let start = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2025,
                    month: 9,
                    day: 15,
                    hour: 12
                )
            )
        )
        let today = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 30,
                    hour: 12
                )
            )
        )

        let dates = editState.editingStartDate(
            start,
            interval: .monthly,
            asOf: today,
            timeZoneIdentifier: "UTC"
        )

        #expect(dates?.startDate == start)
        #expect(
            calendar.dateComponents(
                [.year, .month, .day],
                from: try #require(dates?.nextRenewal)
            ) == DateComponents(year: 2026, month: 8, day: 15)
        )
    }

    @Test("Editing Next Renewal derives one preceding cycle")
    func editingNextRenewalDerivesStartDate() throws {
        let editState = BillingDateEditState()
        let calendar = try #require(
            BillingCalendar.calendar(timeZoneIdentifier: "UTC")
        )
        let renewal = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 2,
                    day: 28,
                    hour: 12
                )
            )
        )

        let dates = editState.editingNextRenewal(
            renewal,
            interval: .monthly,
            timeZoneIdentifier: "UTC"
        )

        #expect(dates?.nextRenewal == renewal)
        #expect(
            calendar.dateComponents(
                [.year, .month, .day],
                from: try #require(dates?.startDate)
            ) == DateComponents(year: 2026, month: 1, day: 28)
        )
    }

    @Test("Changing interval recomputes Next Renewal from Start Date")
    func intervalChangeRecomputesNextRenewal() throws {
        let editState = BillingDateEditState()
        let calendar = try #require(
            BillingCalendar.calendar(timeZoneIdentifier: "UTC")
        )
        let anchor = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 1,
                    day: 15,
                    hour: 12
                )
            )
        )
        let today = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 1,
                    day: 20,
                    hour: 12
                )
            )
        )

        let dates = editState.changingInterval(
            startDate: anchor,
            interval: .yearly,
            asOf: today,
            timeZoneIdentifier: "UTC"
        )

        #expect(
            calendar.dateComponents(
                [.year, .month, .day],
                from: try #require(dates?.nextRenewal)
            ) == DateComponents(year: 2027, month: 1, day: 15)
        )
    }

    @Test("Invalid intervals cannot produce linked billing dates")
    func invalidIntervalCannotProduceLinkedDates() throws {
        let editState = BillingDateEditState()
        let calendar = try #require(
            BillingCalendar.calendar(timeZoneIdentifier: "UTC")
        )
        let anchor = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 1,
                    day: 15,
                    hour: 12
                )
            )
        )

        let dates = editState.editingStartDate(
            anchor,
            interval: .custom(value: 0, unit: .month),
            asOf: anchor,
            timeZoneIdentifier: "UTC"
        )

        #expect(dates == nil)
    }

    @Test("Form renewal defaults use Gregorian billing semantics")
    func renewalDefaultsIgnoreNonGregorianDisplayCalendar() throws {
        var displayCalendar = Calendar(identifier: .islamicCivil)
        displayCalendar.timeZone = try #require(
            TimeZone(identifier: "Asia/Shanghai")
        )
        let start = try #require(
            displayCalendar.date(
                from: DateComponents(
                    year: 1447,
                    month: 8,
                    day: 12,
                    hour: 12
                )
            )
        )
        let billingCalendar = try #require(
            BillingCalendar.calendar(
                timeZoneIdentifier: "Asia/Shanghai"
            )
        )
        let expected = try #require(
            billingCalendar.date(
                byAdding: .month,
                value: 1,
                to: start
            )
        )

        let actual = defaultNextRenewal(
            after: start,
            interval: .monthly,
            timeZoneIdentifier: "Asia/Shanghai"
        )

        #expect(actual == expected)
    }

    @Test("An overflowing custom week default is rejected without trapping")
    func overflowingCustomWeekDoesNotTrap() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)

        let renewal = defaultNextRenewal(
            after: anchor,
            interval: .custom(value: .max, unit: .week),
            timeZoneIdentifier: "UTC"
        )

        #expect(renewal == anchor)
    }

    @Test("Trial billing dates use lifecycle-specific labels")
    func trialBillingDatesUseLifecycleSpecificLabels() {
        #expect(
            billingStartDateLabelKey(isTrial: true) == "Trial Start"
        )
        #expect(
            billingNextDateLabelKey(isTrial: true)
                == "First Paid Charge"
        )
        #expect(
            billingStartDateLabelKey(isTrial: false) == "Start Date"
        )
        #expect(
            billingNextDateLabelKey(isTrial: false) == "Next Renewal"
        )
    }
}
