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

    @Test("Start and anchor edits keep automatic next-renewal updates enabled")
    func startAndAnchorEditsDoNotLockNextRenewal() throws {
        var editState = BillingDateEditState()
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
        let staleRenewal = anchor

        editState.recordUserEdit(.startDate)
        editState.recordUserEdit(.renewalAnchor)
        let recalculated = editState.nextRenewal(
            current: staleRenewal,
            after: anchor,
            interval: .monthly,
            timeZoneIdentifier: "UTC"
        )

        #expect(recalculated != staleRenewal)
        #expect(
            calendar.dateComponents(
                [.year, .month, .day],
                from: recalculated
            ) == DateComponents(year: 2026, month: 2, day: 15)
        )
    }

    @Test("Editing next renewal locks it against offer and anchor changes")
    func nextRenewalEditLocksAutomaticUpdates() {
        var editState = BillingDateEditState()
        let personSelected = Date(timeIntervalSince1970: 1_800_000_000)

        editState.recordUserEdit(.nextRenewal)
        let preserved = editState.nextRenewal(
            current: personSelected,
            after: .distantPast,
            interval: .yearly,
            timeZoneIdentifier: "UTC"
        )

        #expect(preserved == personSelected)
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
}
