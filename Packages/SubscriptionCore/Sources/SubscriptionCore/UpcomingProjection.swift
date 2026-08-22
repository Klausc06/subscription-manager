import Foundation
import Observation

public struct UpcomingTimelineItem: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case expected
        case confirmed
    }

    public let id: String
    public let kind: Kind
    public let subscriptionID: UUID
    public let serviceName: String
    public let date: Date
    public let amount: Money

    public init(
        id: String,
        kind: Kind,
        subscriptionID: UUID,
        serviceName: String,
        date: Date,
        amount: Money
    ) {
        self.id = id
        self.kind = kind
        self.subscriptionID = subscriptionID
        self.serviceName = serviceName
        self.date = date
        self.amount = amount
    }
}

public struct UpcomingCalendarDay: Equatable, Identifiable, Sendable {
    public let date: Date
    public let items: [UpcomingTimelineItem]

    public var id: Date { date }

    public init(date: Date, items: [UpcomingTimelineItem]) {
        self.date = date
        self.items = items
    }
}

/// A presentation-ready month slice of an existing Upcoming timeline. This
/// groups already-resolved charge facts; it does not query persistence or
/// generate billing recurrences.
public struct UpcomingCalendarProjection: Equatable, Sendable {
    public let monthStart: Date
    public let days: [UpcomingCalendarDay]

    public init(
        monthContaining date: Date,
        items: [UpcomingTimelineItem],
        calendar: Calendar
    ) {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date)
        else {
            monthStart = calendar.startOfDay(for: date)
            days = []
            return
        }

        monthStart = monthInterval.start
        let grouped = Dictionary(grouping: items.filter {
            monthInterval.contains($0.date)
        }) { item in
            calendar.startOfDay(for: item.date)
        }
        days = grouped
            .map { date, items in
                UpcomingCalendarDay(
                    date: date,
                    items: items.sorted { lhs, rhs in
                        if lhs.date != rhs.date { return lhs.date < rhs.date }
                        return lhs.id < rhs.id
                    }
                )
            }
            .sorted { $0.date < $1.date }
    }
}

