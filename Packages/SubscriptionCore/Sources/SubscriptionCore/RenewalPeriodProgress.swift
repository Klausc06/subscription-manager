import Foundation

/// How far the current billing period has elapsed and how many whole days
/// remain before the Confirmed Next Renewal.
///
/// Every value is derived in the Fixed Billing Schedule's billing time zone,
/// so a surface rendered on a device in another zone still agrees with the
/// expected charge instead of drifting by a day.
public struct RenewalPeriodProgress: Equatable, Sendable {
    /// The elapsed fraction of the current billing period, clamped to `0...1`.
    /// A schedule that cannot produce a positive period reports `0`.
    public let fraction: Double

    /// Whole days from the current billing day to the renewal billing day.
    /// Never negative, so a past renewal reports `0` rather than a countdown
    /// running backwards.
    public let daysRemaining: Int

    public init(
        schedule: FixedBillingSchedule,
        confirmedNextRenewal: Date,
        asOf now: Date
    ) {
        let calendar = BillingCalendar.calendar(
            timeZoneIdentifier: schedule.timeZoneIdentifier
        ) ?? BillingCalendar.calendar(timeZone: .autoupdatingCurrent)

        // Stepping one interval back from a renewal is the same derivation
        // the Edit flow uses to fill in a Start Date, so this reuses that
        // resolver instead of restating the step. Its guards come with it: a
        // non-finite renewal, an invalid interval, or a step that does not
        // survive negation all return `nil`. Persisted data is not
        // range-checked on the way in, so a custom value of `Int.min` reaches
        // here and plain negation would trap. Anything rejected keeps
        // `periodStart` at the renewal, which is the documented degradation
        // to a zero-length period.
        let periodStart = BillingDateResolver().previousCycleStart(
            before: confirmedNextRenewal,
            interval: schedule.interval,
            timeZone: calendar.timeZone
        ) ?? confirmedNextRenewal

        let total = confirmedNextRenewal.timeIntervalSince(periodStart)
        if total > 0 {
            let elapsed = now.timeIntervalSince(periodStart)
            fraction = min(max(elapsed / total, 0), 1)
        } else {
            fraction = 0
        }

        let wholeDays = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: confirmedNextRenewal)
        ).day ?? 0
        daysRemaining = max(wholeDays, 0)
    }

    /// The elapsed fraction as whole percent, for compact presentation.
    public var percentElapsed: Int {
        Int(fraction * 100)
    }
}
