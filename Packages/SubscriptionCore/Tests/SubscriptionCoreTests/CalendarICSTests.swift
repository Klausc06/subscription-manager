import Foundation
import SubscriptionCore
import Testing

@Suite("Calendar ICS")
struct CalendarICSTests {
    @Test("ICS encodes an all-day event with stable UID URL and alarms")
    func encodesAllDayEvent() throws {
        let startDate = try calendarDate(year: 2026, month: 8, day: 2)
        let endDate = try calendarDate(year: 2026, month: 8, day: 3)
        let event = CalendarProjectionEvent(
            uid: "subscription-20260802@subscription-manager",
            startDate: startDate,
            endDate: endDate,
            title: "Atlas — US$12.99",
            notes: "Pro\nUS$12.99",
            managementURL: URL(string: "https://example.com/manage")!,
            alarmOffsets: [-7, -1],
            timeZoneIdentifier: "GMT"
        )

        let data = try CalendarICSEncoder().encode(
            events: [event],
            generatedAt: startDate
        )
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(text.contains("UID:subscription-20260802@subscription-manager"))
        #expect(text.contains("DTSTART;VALUE=DATE:20260802"))
        #expect(text.contains("DTEND;VALUE=DATE:20260803"))
        #expect(text.contains("URL:https://example.com/manage"))
        #expect(text.contains("TRIGGER:-P7D"))
        #expect(text.contains("TRIGGER:-P1D"))
    }

    @Test("ICS escapes text folds content lines and preserves billing-local dates")
    func escapesFoldsAndUsesBillingLocalDate() throws {
        let utcDate = try calendarDate(
            year: 2026,
            month: 8,
            day: 1,
            hour: 16
        )
        let nextUTCDate = try calendarDate(
            year: 2026,
            month: 8,
            day: 2,
            hour: 16
        )
        let longTitle = "Annual; plan, with a backslash \\" + String(repeating: "界", count: 30)
        let event = CalendarProjectionEvent(
            uid: "subscription-20260802@subscription-manager",
            startDate: utcDate,
            endDate: nextUTCDate,
            title: longTitle,
            notes: "First line\nSecond line",
            managementURL: nil,
            alarmOffsets: [-1],
            timeZoneIdentifier: "Asia/Shanghai"
        )

        let data = try CalendarICSEncoder().encode(
            events: [event],
            generatedAt: utcDate
        )
        let text = try #require(String(data: data, encoding: .utf8))
        let physicalLines = text
            .components(separatedBy: "\r\n")
            .dropLast()

        #expect(text.contains("DTSTART;VALUE=DATE:20260802"))
        #expect(text.contains("SUMMARY:Annual\\; plan\\, with a backslash \\\\"))
        #expect(text.contains("DESCRIPTION:First line\\nSecond line"))
        #expect(text.contains("\r\n "))
        #expect(physicalLines.allSatisfy {
            $0.lengthOfBytes(using: .utf8) <= 75
        })
    }
}

private func calendarDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0
) throws -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.timeZone = TimeZone(secondsFromGMT: 0)
    return try #require(Calendar(identifier: .gregorian).date(from: components))
}
