import Foundation

public struct CalendarICSEncoder: Sendable {
    public init() {}

    public func encode(
        events: [CalendarProjectionEvent],
        generatedAt: Date = Date()
    ) throws -> Data {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Subscription Manager//Calendar Projection//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH"
        ]

        for event in events {
            lines.append(contentsOf: eventLines(event, generatedAt: generatedAt))
        }

        lines.append("END:VCALENDAR")
        let serialized = lines
            .flatMap(foldedContentLines)
            .joined(separator: "\r\n")
            + "\r\n"
        return Data(serialized.utf8)
    }

    private func eventLines(
        _ event: CalendarProjectionEvent,
        generatedAt: Date
    ) -> [String] {
        var lines = [
            "BEGIN:VEVENT",
            "UID:\(escapedText(event.uid))",
            "DTSTAMP:\(utcTimestamp(generatedAt))",
            "DTSTART;VALUE=DATE:\(localDate(event.startDate, timeZoneIdentifier: event.timeZoneIdentifier))",
            "DTEND;VALUE=DATE:\(localDate(event.endDate, timeZoneIdentifier: event.timeZoneIdentifier))",
            "SUMMARY:\(escapedText(event.title))",
            "DESCRIPTION:\(escapedText(event.notes))"
        ]

        if let managementURL = event.managementURL {
            lines.append("URL:\(managementURL.absoluteString)")
        }

        for offset in event.alarmOffsets.filter({ $0 < 0 }).sorted() {
            lines.append(contentsOf: [
                "BEGIN:VALARM",
                "ACTION:DISPLAY",
                "DESCRIPTION:\(escapedText(event.title))",
                "TRIGGER:-P\(abs(offset))D",
                "END:VALARM"
            ])
        }

        lines.append("END:VEVENT")
        return lines
    }

    private func utcTimestamp(_ date: Date) -> String {
        formatted(date, format: "yyyyMMdd'T'HHmmss'Z'", timeZone: .gmt)
    }

    private func localDate(
        _ date: Date,
        timeZoneIdentifier: String
    ) -> String {
        formatted(
            date,
            format: "yyyyMMdd",
            timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
    }

    private func formatted(
        _ date: Date,
        format: String,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func escapedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    private func foldedContentLines(_ line: String) -> [String] {
        var physicalLines: [String] = []
        var segment = ""
        var segmentLength = 0

        for character in line {
            let characterLength = String(character).utf8.count
            let limit = physicalLines.isEmpty ? 75 : 74
            if segmentLength + characterLength > limit, !segment.isEmpty {
                let prefix = physicalLines.isEmpty ? "" : " "
                physicalLines.append(prefix + segment)
                segment = ""
                segmentLength = 0
            }
            segment.append(character)
            segmentLength += characterLength
        }

        let prefix = physicalLines.isEmpty ? "" : " "
        physicalLines.append(prefix + segment)
        return physicalLines
    }
}
