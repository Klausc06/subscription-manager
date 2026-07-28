import Foundation

public enum ExchangeRateConversionError: Error, Equatable, Sendable {
    case missingRate(Currency)
}

public struct ExchangeRateSnapshot: Codable, Equatable, Sendable {
    public let base: Currency
    public let providerDate: Date
    public let fetchedAt: Date
    public let source: String
    public let rates: [Currency: Decimal]

    public init(
        base: Currency,
        providerDate: Date,
        fetchedAt: Date,
        source: String,
        rates: [Currency: Decimal]
    ) {
        self.base = base
        self.providerDate = providerDate
        self.fetchedAt = fetchedAt
        self.source = source
        self.rates = rates
    }

    public func convert(
        _ money: Money,
        to targetCurrency: Currency
    ) throws -> Money {
        let sourceRate = try rate(for: money.currency)
        let targetRate = try rate(for: targetCurrency)
        let sourceAmount = Decimal(money.minorUnits) / 100
        let targetAmount = sourceAmount / sourceRate * targetRate
        var roundedAmount = Decimal()
        var amountForRounding = targetAmount
        NSDecimalRound(&roundedAmount, &amountForRounding, 2, .plain)
        return Money(
            minorUnits: NSDecimalNumber(decimal: roundedAmount * 100).int64Value,
            currency: targetCurrency
        )
    }

    private func rate(for currency: Currency) throws -> Decimal {
        if currency == base {
            return 1
        }
        guard let rate = rates[currency] else {
            throw ExchangeRateConversionError.missingRate(currency)
        }
        return rate
    }
}

public struct ExchangeRateCacheState: Codable, Equatable, Sendable {
    public let snapshot: ExchangeRateSnapshot?
    public let lastAttemptAt: Date?

    public init(snapshot: ExchangeRateSnapshot?, lastAttemptAt: Date?) {
        self.snapshot = snapshot
        self.lastAttemptAt = lastAttemptAt
    }
}

public enum ExchangeRateStatus: Equatable, Sendable {
    case notLoaded
    case fresh(ExchangeRateSnapshot)
    case stale(ExchangeRateSnapshot)
    case unavailable
}

@MainActor
public protocol ExchangeRateSource {
    func fetchRates(
        base: Currency,
        quotes: Set<Currency>
    ) async throws -> ExchangeRateSnapshot
}

@MainActor
public protocol ExchangeRateCache {
    func loadState() throws -> ExchangeRateCacheState?
    func saveState(_ state: ExchangeRateCacheState) throws
}
