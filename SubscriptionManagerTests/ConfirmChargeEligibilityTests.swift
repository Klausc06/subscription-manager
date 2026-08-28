import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("Confirm charge eligibility")
struct ConfirmChargeEligibilityTests {
    private let subscriptionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test("Only an expected occurrence can be confirmed")
    func missingExpectedOccurrenceIsNotEligible() {
        #expect(
            !ConfirmChargeEligibility.isEligible(
                expectedOccurrence: nil,
                confirmedIDs: [],
                now: date("2026-08-01T12:00:00Z"),
                billingTimeZone: TimeZone(secondsFromGMT: 0)!
            )
        )
    }

    @Test("A billing-local day in the future is not eligible")
    func futureBillingDayIsNotEligible() {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let expected = expectedCharge("2026-08-02T00:15:00Z")

        #expect(
            !ConfirmChargeEligibility.isEligible(
                expectedOccurrence: expected,
                confirmedIDs: [],
                now: date("2026-08-01T15:30:00Z"),
                billingTimeZone: timeZone
            )
        )
    }

    @Test("The same billing-local day is eligible")
    func sameBillingDayIsEligible() {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let expected = expectedCharge("2026-08-01T01:00:00Z")

        #expect(
            ConfirmChargeEligibility.isEligible(
                expectedOccurrence: expected,
                confirmedIDs: [],
                now: date("2026-08-01T15:30:00Z"),
                billingTimeZone: timeZone
            )
        )
    }

    @Test("An overdue billing-local day is eligible")
    func overdueBillingDayIsEligible() {
        let expected = expectedCharge("2026-07-31T12:00:00Z")

        #expect(
            ConfirmChargeEligibility.isEligible(
                expectedOccurrence: expected,
                confirmedIDs: [],
                now: date("2026-08-01T12:00:00Z"),
                billingTimeZone: TimeZone(secondsFromGMT: 0)!
            )
        )
    }

    @Test("A previously confirmed occurrence is not eligible")
    func confirmedOccurrenceIsNotEligible() {
        let expected = expectedCharge("2026-08-01T12:00:00Z")

        #expect(
            !ConfirmChargeEligibility.isEligible(
                expectedOccurrence: expected,
                confirmedIDs: [expected.id],
                now: date("2026-08-01T13:00:00Z"),
                billingTimeZone: TimeZone(secondsFromGMT: 0)!
            )
        )
    }

    @Test("A different confirmed occurrence does not block this occurrence")
    func unrelatedConfirmedOccurrenceDoesNotBlock() {
        let expected = expectedCharge("2026-08-01T12:00:00Z")
        let unrelatedID = ScheduledChargeID(
            subscriptionID: subscriptionID,
            year: 2026,
            month: 8,
            day: 2
        )

        #expect(
            ConfirmChargeEligibility.isEligible(
                expectedOccurrence: expected,
                confirmedIDs: [unrelatedID],
                now: date("2026-08-01T13:00:00Z"),
                billingTimeZone: TimeZone(secondsFromGMT: 0)!
            )
        )
    }

    @Test("Eligibility compares billing-local days across UTC boundaries")
    func eligibilityUsesBillingTimeZone() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let expected = expectedCharge("2026-08-02T06:30:00Z")

        #expect(
            ConfirmChargeEligibility.isEligible(
                expectedOccurrence: expected,
                confirmedIDs: [],
                now: date("2026-08-02T06:00:00Z"),
                billingTimeZone: timeZone
            )
        )
    }

    private func expectedCharge(_ scheduledDate: String) -> ExpectedCharge {
        ExpectedCharge(
            id: ScheduledChargeID(
                subscriptionID: subscriptionID,
                year: 2026,
                month: 8,
                day: 1
            ),
            subscriptionID: subscriptionID,
            scheduledDate: date(scheduledDate),
            amount: Money(minorUnits: 1_000, currency: .usd)
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

@Suite("Upcoming month navigation")
struct UpcomingMonthNavigationTests {
    @Test("A wide, loaded month leaves navigation to the native calendar")
    func loadedWideMonthUsesNativeCalendarOnly() {
        #expect(
            UpcomingView.showsNativeMonthCalendar(
                canUseNativeMonthCalendar: true,
                hasUpcomingFailure: false
            )
        )
        #expect(
            !UpcomingView.showsPinnedMonthNavigation(
                canUseNativeMonthCalendar: true,
                hasUpcomingFailure: false
            )
        )
    }

    @Test("A failed month keeps navigation reachable on a wide layout")
    func failedWideMonthKeepsPinnedNavigation() {
        #expect(
            !UpcomingView.showsNativeMonthCalendar(
                canUseNativeMonthCalendar: true,
                hasUpcomingFailure: true
            )
        )
        #expect(
            UpcomingView.showsPinnedMonthNavigation(
                canUseNativeMonthCalendar: true,
                hasUpcomingFailure: true
            )
        )
    }

    @Test("Layouts without the native calendar always pin navigation")
    func layoutsWithoutNativeCalendarPinNavigation() {
        for hasUpcomingFailure in [false, true] {
            #expect(
                !UpcomingView.showsNativeMonthCalendar(
                    canUseNativeMonthCalendar: false,
                    hasUpcomingFailure: hasUpcomingFailure
                )
            )
            #expect(
                UpcomingView.showsPinnedMonthNavigation(
                    canUseNativeMonthCalendar: false,
                    hasUpcomingFailure: hasUpcomingFailure
                )
            )
        }
    }

    @Test("Exactly one month navigation surface is ever mounted")
    func monthNavigationSurfacesAreMutuallyExclusive() {
        for canUseNativeMonthCalendar in [false, true] {
            for hasUpcomingFailure in [false, true] {
                #expect(
                    UpcomingView.showsNativeMonthCalendar(
                        canUseNativeMonthCalendar: canUseNativeMonthCalendar,
                        hasUpcomingFailure: hasUpcomingFailure
                    ) != UpcomingView.showsPinnedMonthNavigation(
                        canUseNativeMonthCalendar: canUseNativeMonthCalendar,
                        hasUpcomingFailure: hasUpcomingFailure
                    )
                )
            }
        }
    }
}
