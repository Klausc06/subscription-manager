import Foundation
import Testing

@testable import SubscriptionCore

@Suite("Renewal period progress")
struct RenewalPeriodProgressTests {
    /// Builds a date at noon in a fixed zone, matching how the app stores a
    /// date-only billing input.
    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12,
        timeZone: String
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar.date(from: components)!
    }

    private func schedule(
        interval: BillingInterval,
        timeZone: String
    ) -> FixedBillingSchedule {
        FixedBillingSchedule(
            interval: interval,
            renewalAnchor: date(2026, 1, 1, timeZone: timeZone),
            timeZoneIdentifier: timeZone
        )
    }

    @Test("Half an elapsed monthly period reports half progress")
    func halfElapsedMonthlyPeriod() {
        // The period runs 2026-02-01 12:00 to 2026-03-01 12:00. February 2026
        // has 28 days, so noon on the 15th is exactly halfway: 14 days
        // elapsed, 14 days remaining.
        let renewal = date(2026, 3, 1, timeZone: "UTC")
        let progress = RenewalPeriodProgress(
            schedule: schedule(interval: .monthly, timeZone: "UTC"),
            confirmedNextRenewal: renewal,
            asOf: date(2026, 2, 15, timeZone: "UTC")
        )

        #expect(abs(progress.fraction - 0.5) < 0.0001)
        #expect(progress.percentElapsed == 50)
        #expect(progress.daysRemaining == 14)
    }

    @Test("Progress clamps before the period starts and after it ends")
    func progressClamps() {
        let renewal = date(2026, 3, 1, timeZone: "UTC")
        let monthly = schedule(interval: .monthly, timeZone: "UTC")

        let before = RenewalPeriodProgress(
            schedule: monthly,
            confirmedNextRenewal: renewal,
            asOf: date(2025, 12, 1, timeZone: "UTC")
        )
        let after = RenewalPeriodProgress(
            schedule: monthly,
            confirmedNextRenewal: renewal,
            asOf: date(2026, 6, 1, timeZone: "UTC")
        )

        #expect(before.fraction == 0)
        #expect(after.fraction == 1)
    }

    @Test("A past renewal never counts down below zero days")
    func pastRenewalReportsZeroDays() {
        let progress = RenewalPeriodProgress(
            schedule: schedule(interval: .monthly, timeZone: "UTC"),
            confirmedNextRenewal: date(2026, 2, 1, timeZone: "UTC"),
            asOf: date(2026, 4, 10, timeZone: "UTC")
        )

        #expect(progress.daysRemaining == 0)
    }

    /// The regression this type exists for: the remaining-day count must be
    /// measured in the billing time zone, not wherever the device sits.
    @Test("Remaining days follow the billing time zone, not the device")
    func remainingDaysUseBillingTimeZone() {
        // Stored at noon Tokyo on 1 March. Read from the same instant, that is
        // still 03:00 UTC on 1 March, so both zones agree the renewal is that
        // calendar day.
        let renewal = date(2026, 3, 1, timeZone: "Asia/Tokyo")

        // "Now" is 20:00 UTC on 28 February, which is already 05:00 on
        // 1 March in Tokyo. In Tokyo the renewal is today (0 days away); a
        // device-time-zone calculation in UTC would claim it is tomorrow.
        let now = date(2026, 2, 28, hour: 20, timeZone: "UTC")

        let tokyoProgress = RenewalPeriodProgress(
            schedule: schedule(interval: .monthly, timeZone: "Asia/Tokyo"),
            confirmedNextRenewal: renewal,
            asOf: now
        )
        let utcProgress = RenewalPeriodProgress(
            schedule: schedule(interval: .monthly, timeZone: "UTC"),
            confirmedNextRenewal: renewal,
            asOf: now
        )

        #expect(tokyoProgress.daysRemaining == 0)
        #expect(utcProgress.daysRemaining == 1)
    }

    @Test("An unusable time zone identifier falls back to the device zone")
    func unusableTimeZoneFallsBack() {
        // The contract is a specific fallback, not merely a finite value: an
        // unresolvable identifier reads as `.autoupdatingCurrent`. Naming that
        // zone explicitly gives the reference progress to match.
        //
        // Both readings resolve through the running machine's zone, so what
        // this catches is a fallback pinned to some other named zone. It does
        // not separate a fallback whose offset equals the device's: on a UTC
        // machine a `.gmt` fallback reads the same and passes.
        let renewal = date(2026, 3, 1, timeZone: "UTC")
        let now = date(2026, 2, 15, hour: 23, timeZone: "UTC")

        let unusable = RenewalPeriodProgress(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: date(2026, 1, 1, timeZone: "UTC"),
                timeZoneIdentifier: "Not/AZone"
            ),
            confirmedNextRenewal: renewal,
            asOf: now
        )
        let deviceZone = RenewalPeriodProgress(
            schedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: date(2026, 1, 1, timeZone: "UTC"),
                timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
            ),
            confirmedNextRenewal: renewal,
            asOf: now
        )

        #expect(unusable.fraction == deviceZone.fraction)
        #expect(unusable.daysRemaining == deviceZone.daysRemaining)
    }

    /// Each row names the expected period start as a literal date rather than
    /// stepping back from the renewal, so a wrong derivation cannot agree with
    /// its own expectation. No expected start sits on a month end, which is
    /// what lets the day after it be written as `startDay + 1`.
    @Test(
        "Every interval steps back exactly one billing period",
        arguments: [
            (BillingInterval.weekly, 2026, 7, 25, 7),
            (BillingInterval.monthly, 2026, 7, 1, 31),
            (BillingInterval.quarterly, 2026, 5, 1, 92),
            (BillingInterval.halfYearly, 2026, 2, 1, 181),
            (BillingInterval.yearly, 2025, 8, 1, 365),
            (BillingInterval.custom(value: 10, unit: .day), 2026, 7, 22, 10),
            (BillingInterval.custom(value: 2, unit: .week), 2026, 7, 18, 14),
        ]
    )
    func intervalStepsOnePeriod(
        interval: BillingInterval,
        startYear: Int,
        startMonth: Int,
        startDay: Int,
        spanDays: Int
    ) {
        // Renewal on 1 August 2026; "now" is the renewal instant, so the
        // elapsed fraction is 1 and the period length is the interval itself.
        let renewal = date(2026, 8, 1, timeZone: "UTC")
        let progress = RenewalPeriodProgress(
            schedule: schedule(interval: interval, timeZone: "UTC"),
            confirmedNextRenewal: renewal,
            asOf: renewal
        )

        #expect(progress.fraction == 1)
        #expect(progress.daysRemaining == 0)

        // Nothing has elapsed on the expected period start, and something has
        // elapsed the day after. The second reading is what pins the start
        // down: a period that begins too early is already under way on the
        // expected start day, yet the clamp to `0...1` hides that from the
        // first reading alone.
        let atStart = RenewalPeriodProgress(
            schedule: schedule(interval: interval, timeZone: "UTC"),
            confirmedNextRenewal: renewal,
            asOf: date(startYear, startMonth, startDay, timeZone: "UTC")
        )
        let afterStart = RenewalPeriodProgress(
            schedule: schedule(interval: interval, timeZone: "UTC"),
            confirmedNextRenewal: renewal,
            asOf: date(startYear, startMonth, startDay + 1, timeZone: "UTC")
        )

        #expect(atStart.fraction == 0)
        #expect(afterStart.fraction > 0)

        // Measured between two literal dates now, so it no longer restates
        // the value used to build the period start.
        #expect(atStart.daysRemaining == spanDays)
    }

    /// A persisted custom value is never range-checked on the way in: the
    /// decoder takes any `Int` and the raw-value parser accepts
    /// `"custom:-9223372036854775808:day"`, so `Int.min` reaches this type
    /// from imported storage. Negating it to step back one period traps at
    /// runtime, which kills the process rather than failing a check, so the
    /// interval has to be rejected before the calendar step is applied.
    @Test("An out-of-range custom interval reports no progress")
    func outOfRangeCustomIntervalReportsNoProgress() {
        let renewal = date(2026, 3, 1, timeZone: "UTC")
        let progress = RenewalPeriodProgress(
            schedule: schedule(
                interval: .custom(value: Int.min, unit: .day),
                timeZone: "UTC"
            ),
            confirmedNextRenewal: renewal,
            asOf: date(2026, 2, 15, timeZone: "UTC")
        )

        // The documented degradation for a schedule that cannot produce a
        // positive period, reached here without a new error path.
        #expect(progress.fraction == 0)
        #expect(progress.percentElapsed == 0)

        // The day count never negates the step, so it stays correct: noon on
        // 15 February to noon on 1 March is 14 whole days.
        #expect(progress.daysRemaining == 14)
    }
}

@Suite("Billing interval calendar step")
struct BillingIntervalCalendarStepTests {
    @Test("Named intervals map to their calendar step")
    func namedIntervals() {
        #expect(BillingInterval.weekly.calendarStep == (.weekOfYear, 1))
        #expect(BillingInterval.monthly.calendarStep == (.month, 1))
        #expect(BillingInterval.quarterly.calendarStep == (.month, 3))
        #expect(BillingInterval.halfYearly.calendarStep == (.month, 6))
        #expect(BillingInterval.yearly.calendarStep == (.year, 1))
    }

    @Test("Custom intervals carry their own unit and value")
    func customIntervals() {
        #expect(
            BillingInterval.custom(value: 5, unit: .day).calendarStep
                == (.day, 5)
        )
        #expect(
            BillingInterval.custom(value: 3, unit: .week).calendarStep
                == (.weekOfYear, 3)
        )
        #expect(
            BillingInterval.custom(value: 4, unit: .month).calendarStep
                == (.month, 4)
        )
        #expect(
            BillingInterval.custom(value: 2, unit: .year).calendarStep
                == (.year, 2)
        )
    }
}
