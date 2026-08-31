import Foundation

public enum BillingCalendar {
    public static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    public static func calendar(
        timeZoneIdentifier: String
    ) -> Calendar? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return nil
        }
        return calendar(timeZone: timeZone)
    }
}

public enum BillingIntervalUnit: String, CaseIterable, Codable, Sendable {
    case day
    case week
    case month
    case year
}

public enum BillingInterval: Codable, Equatable, RawRepresentable, Sendable {
    case weekly
    case monthly
    case quarterly
    case halfYearly
    case yearly
    case custom(value: Int, unit: BillingIntervalUnit)

    public init?(rawValue: String) {
        switch rawValue {
        case "weekly":
            self = .weekly
        case "monthly":
            self = .monthly
        case "quarterly":
            self = .quarterly
        case "halfYearly":
            self = .halfYearly
        case "yearly":
            self = .yearly
        default:
            let components = rawValue.split(
                separator: ":",
                omittingEmptySubsequences: false
            )
            guard components.count == 3,
                  components[0] == "custom",
                  let value = Int(components[1]),
                  let unit = BillingIntervalUnit(
                      rawValue: String(components[2])
                  )
            else {
                return nil
            }
            self = .custom(value: value, unit: unit)
        }
    }

    public var rawValue: String {
        switch self {
        case .weekly:
            "weekly"
        case .monthly:
            "monthly"
        case .quarterly:
            "quarterly"
        case .halfYearly:
            "halfYearly"
        case .yearly:
            "yearly"
        case .custom(let value, let unit):
            "custom:\(value):\(unit.rawValue)"
        }
    }

    public var storageIdentifier: String {
        switch self {
        case .custom:
            "custom"
        default:
            rawValue
        }
    }

    public var customValue: Int? {
        guard case .custom(let value, _) = self else {
            return nil
        }
        return value
    }

    public var customUnit: BillingIntervalUnit? {
        guard case .custom(_, let unit) = self else {
            return nil
        }
        return unit
    }

    public var isValid: Bool {
        guard case .custom(let value, let unit) = self else {
            return true
        }
        guard value > 0 else {
            return false
        }
        guard unit == .week else {
            return true
        }
        return !value.multipliedReportingOverflow(by: 7).overflow
    }

    /// The single calendar step that advances one billing occurrence.
    ///
    /// This is the canonical mapping for callers that add or subtract whole
    /// occurrences. `WorkspaceScheduleMath` still keeps two forms of its own
    /// because it multiplies the interval by an occurrence index and so needs
    /// it normalized to a day or month scalar (weekly as 7 days, yearly as
    /// 12 months), which this `(component, value)` shape cannot supply.
    var calendarStep: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly:
            (.weekOfYear, 1)
        case .monthly:
            (.month, 1)
        case .quarterly:
            (.month, 3)
        case .halfYearly:
            (.month, 6)
        case .yearly:
            (.year, 1)
        case .custom(let value, let unit):
            switch unit {
            case .day:
                (.day, value)
            case .week:
                (.weekOfYear, value)
            case .month:
                (.month, value)
            case .year:
                (.year, value)
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawValue = try? singleValue.decode(String.self),
           let interval = BillingInterval(rawValue: rawValue)
        {
            self = interval
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(
            String.self,
            forKey: .rawValue
        )
        if rawValue == "custom" {
            self = .custom(
                value: try container.decode(
                    Int.self,
                    forKey: .customValue
                ),
                unit: try container.decode(
                    BillingIntervalUnit.self,
                    forKey: .customUnit
                )
            )
        } else if let interval = BillingInterval(rawValue: rawValue) {
            self = interval
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .rawValue,
                in: container,
                debugDescription: "Unsupported billing interval."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storageIdentifier, forKey: .rawValue)
        if case .custom(let value, let unit) = self {
            try container.encode(value, forKey: .customValue)
            try container.encode(unit, forKey: .customUnit)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case rawValue
        case customValue
        case customUnit
    }
}

@available(*, deprecated, renamed: "BillingInterval")
public typealias BillingCycle = BillingInterval

/// A recurrence defined by one known occurrence and a fixed interval.
public struct FixedBillingSchedule: Codable, Equatable, Sendable {
    public let interval: BillingInterval

    /// A date on which this subscription renews. **The anchor is itself an
    /// occurrence**, not the cycle that precedes one: the schedule is
    /// `renewalAnchor + n * interval` for `n >= 0`.
    ///
    /// This was undocumented, and two readings of it coexisted long enough to
    /// ship a defect (#125). `BillingDateResolver.expectedOccurrences` already
    /// assumed the reading above, while `nextRenewal(afterStart:)` answers a
    /// deliberately different question -- the first renewal *strictly after* a
    /// given date -- so feeding it an anchor returns the one after the anchor.
    /// Callers that want "the next renewal from here, the anchor included" want
    /// `firstOccurrence(onOrAfter:schedule:)`.
    ///
    /// Each occurrence is derived from the anchor rather than from its
    /// predecessor, so `Calendar` clamping never accumulates: a Jan 31 anchor
    /// yields Feb 28, Mar 31, Apr 30 rather than drifting to the 28th. That
    /// property only holds while the anchor keeps its own day-of-month, which is
    /// why deriving an anchor by subtracting an interval from a month-end date
    /// destroys the schedule.
    public let renewalAnchor: Date

    public let timeZoneIdentifier: String

    public init(
        interval: BillingInterval,
        renewalAnchor: Date,
        timeZoneIdentifier: String
    ) {
        self.interval = interval
        self.renewalAnchor = renewalAnchor
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public struct ScheduledChargeID: Codable, Equatable, Hashable, Sendable {
    public let subscriptionID: UUID
    public let year: Int
    public let month: Int
    public let day: Int

    public init(
        subscriptionID: UUID,
        year: Int,
        month: Int,
        day: Int
    ) {
        self.subscriptionID = subscriptionID
        self.year = year
        self.month = month
        self.day = day
    }
}

public struct ConfirmedCharge: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let chargedDate: Date
    public let amount: Money
    public let sourceScheduledChargeID: ScheduledChargeID?

    public init(
        id: UUID,
        chargedDate: Date,
        amount: Money,
        sourceScheduledChargeID: ScheduledChargeID? = nil
    ) {
        self.id = id
        self.chargedDate = chargedDate
        self.amount = amount
        self.sourceScheduledChargeID = sourceScheduledChargeID
    }
}

public struct PriceChange: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let effectiveDate: Date
    public let amount: Money

    public init(id: UUID, effectiveDate: Date, amount: Money) {
        self.id = id
        self.effectiveDate = effectiveDate
        self.amount = amount
    }
}
