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

    public static func displayDay(
        for instant: Date,
        billingTimeZoneIdentifier: String,
        displayCalendar: Calendar
    ) -> Date {
        guard let billingCalendar = calendar(
            timeZoneIdentifier: billingTimeZoneIdentifier
        ) else {
            return displayCalendar.startOfDay(for: instant)
        }
        let components = billingCalendar.dateComponents(
            [.year, .month, .day],
            from: instant
        )
        var displayGregorianCalendar = Calendar(identifier: .gregorian)
        displayGregorianCalendar.locale = Locale(identifier: "en_US_POSIX")
        displayGregorianCalendar.timeZone = displayCalendar.timeZone
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let displayDate = displayGregorianCalendar.date(
                  from: DateComponents(year: year, month: month, day: day)
              )
        else {
            return displayCalendar.startOfDay(for: instant)
        }
        return displayCalendar.startOfDay(for: displayDate)
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

public struct FixedBillingSchedule: Codable, Equatable, Sendable {
    public let interval: BillingInterval
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
