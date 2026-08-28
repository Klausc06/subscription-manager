import Foundation
import Observation

public enum Currency: String, CaseIterable, Codable, Hashable, Sendable {
    case cny = "CNY"
    case usd = "USD"
    case eur = "EUR"
}

public struct Money: Codable, Equatable, Sendable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }
}

public struct ServiceIdentity: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ExpectedCharge: Codable, Equatable, Sendable {
    public let id: ScheduledChargeID
    public let subscriptionID: UUID
    public let scheduledDate: Date
    public let amount: Money

    public init(
        id: ScheduledChargeID,
        subscriptionID: UUID,
        scheduledDate: Date,
        amount: Money
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.scheduledDate = scheduledDate
        self.amount = amount
    }
}
