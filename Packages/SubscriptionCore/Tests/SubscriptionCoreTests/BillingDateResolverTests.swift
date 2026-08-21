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
