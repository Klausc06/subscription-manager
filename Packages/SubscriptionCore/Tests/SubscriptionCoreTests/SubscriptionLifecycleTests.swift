import Foundation
@testable import SubscriptionCore
import Testing

@Suite("Subscription lifecycle")
struct SubscriptionLifecycleTests {
    @Test("Trial becomes active for the whole first paid local day")
    func trialBoundaryUsesBillingLocalDay() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let firstPaidCharge = try date(
            year: 2026, month: 3, day: 8, hour: 12, timeZone: timeZone
        )
        let lifecycle = SubscriptionLifecycle.trial(
            firstPaidChargeAt: firstPaidCharge
        )

        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 3, day: 7, hour: 23, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .trial
        )
        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 3, day: 8, hour: 1, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .active
        )
        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 3, day: 9, hour: 12, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .active
        )
    }

    @Test("Cancelled access expires for the whole access-until local day")
    func cancellationBoundaryUsesBillingLocalDay() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let lifecycle = SubscriptionLifecycle.cancelled(
            cancelledAt: try date(
                year: 2026, month: 7, day: 1, hour: 12, timeZone: timeZone
            ),
            accessUntil: try date(
                year: 2026, month: 7, day: 31, hour: 12, timeZone: timeZone
            )
        )

        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 7, day: 30, hour: 23, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .cancelledWithAccess
        )
        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 7, day: 31, hour: 1, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .expired
        )
        #expect(
            lifecycle.status(
                asOf: try date(
                    year: 2026, month: 8, day: 1, hour: 12, timeZone: timeZone
                ),
                timeZone: timeZone
            ) == .expired
        )
    }
}

private func date(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    timeZone: TimeZone
) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return try #require(
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )
    )
}
