import Foundation

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
            return nil
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
        case .custom:
            "custom"
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
        guard case .custom(let value, _) = self else {
            return true
        }
        return value > 0
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

public struct ConfirmedCharge: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let chargedDate: Date
    public let amount: Money

    public init(id: UUID, chargedDate: Date, amount: Money) {
        self.id = id
        self.chargedDate = chargedDate
        self.amount = amount
    }
}
