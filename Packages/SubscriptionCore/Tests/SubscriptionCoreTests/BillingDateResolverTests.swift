import Foundation
@testable import SubscriptionCore
import Testing

@Suite("Billing date resolver")
struct BillingDateResolverTests {
    @Test("An old monthly start finds the first renewal after today")
    func oldMonthlyStartFindsUpcomingRenewal() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let resolver = BillingDateResolver()
        let start = try date(
            year: 2025,
            month: 9,
            day: 15,
            calendar: calendar
        )
        let today = try date(
            year: 2026,
            month: 7,
            day: 30,
            calendar: calendar
        )

        let renewal = resolver.nextRenewal(
            afterStart: start,
            interval: .monthly,
            asOf: today,
            timeZone: timeZone
        )
        let expected = try date(
            year: 2026,
            month: 8,
            day: 15,
            calendar: calendar
        )

        #expect(renewal == expected)
    }

    @Test(
        "Every supported interval finds its next renewal after today",
        arguments: [
            (BillingInterval.weekly, 2026, 1, 22),
            (BillingInterval.quarterly, 2026, 4, 15),
            (BillingInterval.halfYearly, 2026, 7, 15),
            (BillingInterval.yearly, 2027, 1, 15),
            (BillingInterval.custom(value: 10, unit: .day), 2026, 1, 25),
            (BillingInterval.custom(value: 2, unit: .week), 2026, 1, 29),
            (BillingInterval.custom(value: 2, unit: .month), 2026, 3, 15),
            (BillingInterval.custom(value: 2, unit: .year), 2028, 1, 15),
        ]
    )
    func supportedIntervalsFindUpcomingRenewal(
        interval: BillingInterval,
        expectedYear: Int,
        expectedMonth: Int,
        expectedDay: Int
    ) throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let start = try date(
            year: 2026,
            month: 1,
            day: 15,
            calendar: calendar
        )
        let expected = try date(
            year: expectedYear,
            month: expectedMonth,
            day: expectedDay,
            calendar: calendar
        )

        let renewal = BillingDateResolver().nextRenewal(
            afterStart: start,
            interval: interval,
            asOf: start,
            timeZone: timeZone
        )

        #expect(renewal == expected)
    }

    @Test("A February renewal reverses to the same January day")
    func februaryRenewalFindsPreviousMonthlyStart() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let renewal = try date(
            year: 2026,
            month: 2,
            day: 28,
            calendar: calendar
        )
        let expected = try date(
            year: 2026,
            month: 1,
            day: 28,
            calendar: calendar
        )

        let start = BillingDateResolver().previousCycleStart(
            before: renewal,
            interval: .monthly,
            timeZone: timeZone
        )

        #expect(start == expected)
    }

    @Test("A month-end renewal reverses to a clamped previous start")
    func monthEndRenewalClampsPreviousMonthlyStart() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let renewal = try date(
            year: 2026,
            month: 10,
            day: 31,
            calendar: calendar
        )
        // Sep 31 does not exist, so the previous start clamps to Sep 30 and
        // no longer carries the renewal's day-of-month.
        let expected = try date(
            year: 2026,
            month: 9,
            day: 30,
            calendar: calendar
        )

        let start = BillingDateResolver().previousCycleStart(
            before: renewal,
            interval: .monthly,
            timeZone: timeZone
        )

        #expect(start == expected)
    }

    @Test("An occurrence on today advances to the following cycle")
    func occurrenceOnTodayIsNotTheNextRenewal() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let start = try date(
            year: 2026,
            month: 1,
            day: 15,
            calendar: calendar
        )
        let today = try date(
            year: 2026,
            month: 2,
            day: 15,
            calendar: calendar
        )
        let expected = try date(
            year: 2026,
            month: 3,
            day: 15,
            calendar: calendar
        )

        let renewal = BillingDateResolver().nextRenewal(
            afterStart: start,
            interval: .monthly,
            asOf: today,
            timeZone: timeZone
        )

        #expect(renewal == expected)
    }

    @Test("A future start still advances by one complete interval")
    func futureStartAdvancesOneInterval() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let today = try date(
            year: 2026,
            month: 7,
            day: 30,
            calendar: calendar
        )
        let start = try date(
            year: 2026,
            month: 8,
            day: 15,
            calendar: calendar
        )
        let expected = try date(
            year: 2026,
            month: 9,
            day: 15,
            calendar: calendar
        )

        let renewal = BillingDateResolver().nextRenewal(
            afterStart: start,
            interval: .monthly,
            asOf: today,
            timeZone: timeZone
        )

        #expect(renewal == expected)
    }

    @Test("A January month-end anchor progresses to March month-end")
    func januaryMonthEndProgression() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let start = try date(
            year: 2026,
            month: 1,
            day: 31,
            calendar: calendar
        )
        let today = try date(
            year: 2026,
            month: 2,
            day: 28,
            calendar: calendar
        )
        let expected = try date(
            year: 2026,
            month: 3,
            day: 31,
            calendar: calendar
        )

        let renewal = BillingDateResolver().nextRenewal(
            afterStart: start,
            interval: .monthly,
            asOf: today,
            timeZone: timeZone
        )

        #expect(renewal == expected)
    }

    @Test("A leap-day yearly anchor follows Gregorian calendar arithmetic")
    func leapDayYearlyProgression() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let start = try date(
            year: 2024,
            month: 2,
            day: 29,
            calendar: calendar
        )
        let today = try date(
            year: 2025,
            month: 2,
            day: 28,
            calendar: calendar
        )
        let expected = try date(
            year: 2026,
            month: 2,
            day: 28,
            calendar: calendar
        )

        let renewal = BillingDateResolver().nextRenewal(
            afterStart: start,
            interval: .yearly,
            asOf: today,
            timeZone: timeZone
        )

        #expect(renewal == expected)
    }

    @Test("Weekly recurrence preserves billing-local time across DST")
    func weeklyRecurrencePreservesLocalTimeAcrossDST() throws {
        let timeZone = try #require(
            TimeZone(identifier: "America/Los_Angeles")
        )
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let start = try date(
            year: 2026,
            month: 3,
            day: 1,
            calendar: calendar
        )
        let today = try date(
            year: 2026,
            month: 3,
            day: 7,
            calendar: calendar
        )

        let renewal = try #require(
            BillingDateResolver().nextRenewal(
                afterStart: start,
                interval: .weekly,
                asOf: today,
                timeZone: timeZone
            )
        )
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour],
            from: renewal
        )

        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 8)
        #expect(components.hour == 12)
    }

    @Test("Invalid and non-representable custom intervals return nil")
    func invalidAndOverflowingCustomIntervalsReturnNil() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let start = try date(
            year: 2026,
            month: 1,
            day: 15,
            calendar: calendar
        )

        let invalid = BillingDateResolver().nextRenewal(
            afterStart: start,
            interval: .custom(value: 0, unit: .month),
            asOf: start,
            timeZone: timeZone
        )
        let overflowing = BillingDateResolver().nextRenewal(
            afterStart: start,
            interval: .custom(value: Int.max, unit: .week),
            asOf: start,
            timeZone: timeZone
        )

        #expect(invalid == nil)
        #expect(overflowing == nil)
    }

    @Test("Expected occurrences are range-bound and count-limited")
    func expectedOccurrencesAreBounded() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let anchor = try date(
            year: 2025,
            month: 1,
            day: 31,
            calendar: calendar
        )
        let rangeStart = try date(
            year: 2025,
            month: 2,
            day: 1,
            calendar: calendar
        )
        let rangeEnd = try date(
            year: 2025,
            month: 4,
            day: 30,
            calendar: calendar
        )
        let expected = [
            try date(
                year: 2025,
                month: 2,
                day: 28,
                calendar: calendar
            ),
            try date(
                year: 2025,
                month: 3,
                day: 31,
                calendar: calendar
            ),
        ]
        let schedule = FixedBillingSchedule(
            interval: .monthly,
            renewalAnchor: anchor,
            timeZoneIdentifier: timeZone.identifier
        )

        let occurrences = BillingDateResolver().expectedOccurrences(
            in: rangeStart...rangeEnd,
            schedule: schedule,
            limit: 2
        )

        #expect(occurrences == expected)
    }

    @Test("Non-finite dates fail closed without calendar iteration")
    func nonFiniteDatesFailClosed() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let invalidStart = Date(
            timeIntervalSinceReferenceDate: .nan
        )
        let invalidToday = Date(
            timeIntervalSinceReferenceDate: .infinity
        )

        let startResult = BillingDateResolver().nextRenewal(
            afterStart: invalidStart,
            interval: .monthly,
            asOf: Date(),
            timeZone: timeZone
        )
        let todayResult = BillingDateResolver().nextRenewal(
            afterStart: Date(),
            interval: .monthly,
            asOf: invalidToday,
            timeZone: timeZone
        )

        #expect(startResult == nil)
        #expect(todayResult == nil)
    }
}

private func date(
    year: Int,
    month: Int,
    day: Int,
    calendar: Calendar
) throws -> Date {
    try #require(
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )
    )
}

@Suite("Billing date resolver first occurrence")
struct BillingDateResolverFirstOccurrenceTests {
    /// The distinction `nextRenewal(afterStart:)` cannot express, and the reason
    /// #125 shipped: the anchor is itself an occurrence.
    @Test("An anchor on the target day is the first occurrence")
    func anchorOnTargetDayIsReturned() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let anchor = try date(year: 2026, month: 10, day: 31, calendar: calendar)

        #expect(
            BillingDateResolver().firstOccurrence(
                onOrAfter: anchor,
                schedule: schedule(anchor: anchor, interval: .monthly)
            ) == anchor
        )
    }

    @Test("The same anchor is excluded by nextRenewal(afterStart:)")
    func nextRenewalExcludesTheAnchor() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let anchor = try date(year: 2026, month: 10, day: 31, calendar: calendar)
        let expected = try date(
            year: 2026,
            month: 11,
            day: 30,
            calendar: calendar
        )

        // Pinned so the two contracts stay legible to the next reader rather
        // than being rediscovered from a `max(1, ...)` in the implementation.
        #expect(
            BillingDateResolver().nextRenewal(
                afterStart: anchor,
                interval: .monthly,
                asOf: anchor,
                timeZone: timeZone
            ) == expected
        )
    }

    @Test("A month-end anchor does not drift across occurrences")
    func monthEndAnchorDoesNotDrift() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let anchor = try date(year: 2026, month: 10, day: 31, calendar: calendar)
        let resolver = BillingDateResolver()
        let monthly = schedule(anchor: anchor, interval: .monthly)

        // November clamps to the 30th, and December must return to the 31st.
        // Deriving each occurrence from the anchor is what makes that hold;
        // chaining from the clamped November date would give Dec 30.
        let expectations = [
            (month: 11, day: 30),
            (month: 12, day: 31),
        ]
        var probe = anchor
        for expectation in expectations {
            let nextDay = try #require(
                calendar.date(byAdding: .day, value: 1, to: probe)
            )
            let occurrence = try #require(
                resolver.firstOccurrence(onOrAfter: nextDay, schedule: monthly)
            )
            let components = calendar.dateComponents(
                [.month, .day],
                from: occurrence
            )
            #expect(components.month == expectation.month)
            #expect(components.day == expectation.day)
            probe = occurrence
        }
    }

    @Test("A target between occurrences finds the following one")
    func targetBetweenOccurrencesFindsTheFollowing() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let anchor = try date(year: 2026, month: 3, day: 10, calendar: calendar)
        let target = try date(year: 2026, month: 5, day: 1, calendar: calendar)
        let expected = try date(year: 2026, month: 6, day: 10, calendar: calendar)

        #expect(
            BillingDateResolver().firstOccurrence(
                onOrAfter: target,
                schedule: schedule(anchor: anchor, interval: .quarterly)
            ) == expected
        )
    }

    @Test("A target before the anchor returns the anchor")
    func targetBeforeAnchorReturnsTheAnchor() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let anchor = try date(year: 2026, month: 10, day: 31, calendar: calendar)
        let target = try date(year: 2026, month: 1, day: 1, calendar: calendar)

        #expect(
            BillingDateResolver().firstOccurrence(
                onOrAfter: target,
                schedule: schedule(anchor: anchor, interval: .monthly)
            ) == anchor
        )
    }

    @Test("An unknown time zone identifier fails closed")
    func unknownTimeZoneFailsClosed() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let anchor = try date(year: 2026, month: 10, day: 31, calendar: calendar)

        #expect(
            BillingDateResolver().firstOccurrence(
                onOrAfter: anchor,
                schedule: FixedBillingSchedule(
                    interval: .monthly,
                    renewalAnchor: anchor,
                    timeZoneIdentifier: "Not/AZone"
                )
            ) == nil
        )
    }

    @Test("An invalid custom interval fails closed")
    func invalidIntervalFailsClosed() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let calendar = BillingCalendar.calendar(timeZone: timeZone)
        let anchor = try date(year: 2026, month: 10, day: 31, calendar: calendar)

        #expect(
            BillingDateResolver().firstOccurrence(
                onOrAfter: anchor,
                schedule: schedule(
                    anchor: anchor,
                    interval: .custom(value: 0, unit: .month)
                )
            ) == nil
        )
    }

    private func schedule(
        anchor: Date,
        interval: BillingInterval
    ) -> FixedBillingSchedule {
        FixedBillingSchedule(
            interval: interval,
            renewalAnchor: anchor,
            timeZoneIdentifier: "UTC"
        )
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) throws -> Date {
        try #require(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: 12
                )
            )
        )
    }
}
