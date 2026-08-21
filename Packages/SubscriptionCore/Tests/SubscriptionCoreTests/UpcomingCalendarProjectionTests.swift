import Foundation
@testable import SubscriptionCore
import Testing

@Suite("Upcoming calendar projection")
struct UpcomingCalendarProjectionTests {
    @Test("A month projection groups timeline items by billing-local day")
    func groupsItemsByDayWithinSelectedMonth() throws {
        let calendar = utcCalendar()
        let month = try date(year: 2026, month: 8, day: 1, calendar: calendar)
        let fourth = try date(year: 2026, month: 8, day: 4, calendar: calendar)
        let twentieth = try date(year: 2026, month: 8, day: 20, calendar: calendar)
        let outsideMonth = try date(
            year: 2026,
            month: 9,
            day: 1,
            calendar: calendar
        )
        let subscriptionID = UUID(
            uuidString: "12345678-1234-1234-1234-123456789ABC"
        )!
        let items = [
            item(id: "expected-fourth", kind: .expected, date: fourth,
                 subscriptionID: subscriptionID),
            item(id: "confirmed-fourth", kind: .confirmed, date: fourth,
                 subscriptionID: subscriptionID),
            item(id: "expected-twentieth", kind: .expected, date: twentieth,
                 subscriptionID: subscriptionID),
            item(id: "outside-month", kind: .expected, date: outsideMonth,
                 subscriptionID: subscriptionID),
        ]

        let projection = UpcomingCalendarProjection(
            monthContaining: month,
            items: items,
            calendar: calendar
        )

        #expect(projection.days.map(\.date) == [
            calendar.startOfDay(for: fourth),
            calendar.startOfDay(for: twentieth),
        ])
        #expect(projection.days[0].items.map(\.id) == [
            "confirmed-fourth",
            "expected-fourth",
        ])
        #expect(projection.days[1].items.map(\.id) == ["expected-twentieth"])
        let selectedDay = calendar.startOfDay(for: fourth)
        #expect(
            projection.days.first(where: { $0.date == selectedDay })?.items.count == 2
        )
    }

    private func item(
        id: String,
        kind: UpcomingTimelineItem.Kind,
        date: Date,
        subscriptionID: UUID
    ) -> UpcomingTimelineItem {
        UpcomingTimelineItem(
            id: id,
            kind: kind,
            subscriptionID: subscriptionID,
            serviceName: "Example",
            date: date,
            amount: Money(minorUnits: 999, currency: .usd)
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
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
