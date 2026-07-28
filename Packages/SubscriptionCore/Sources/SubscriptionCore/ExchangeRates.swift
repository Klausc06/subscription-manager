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

public enum SpendingReportMode: String, CaseIterable, Codable, Sendable {
    case expected
    case confirmed
}

public struct SpendingInsightItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let subscriptionID: UUID
    public let serviceName: String
    public let category: String
    public let date: Date
    public let originalAmount: Money
    public let convertedAmount: Money

    public init(
        id: String,
        subscriptionID: UUID,
        serviceName: String,
        category: String,
        date: Date,
        originalAmount: Money,
        convertedAmount: Money
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.serviceName = serviceName
        self.category = category
        self.date = date
        self.originalAmount = originalAmount
        self.convertedAmount = convertedAmount
    }
}

public struct SpendingMonthlyTotal: Equatable, Identifiable, Sendable {
    public let month: Date
    public let amount: Money

    public var id: Date { month }

    public init(month: Date, amount: Money) {
        self.month = month
        self.amount = amount
    }
}

public struct SpendingCategoryTotal: Equatable, Identifiable, Sendable {
    public let category: String
    public let amount: Money

    public var id: String { category }

    public init(category: String, amount: Money) {
        self.category = category
        self.amount = amount
    }
}

public struct SpendingInsights: Equatable, Sendable {
    public let mode: SpendingReportMode
    public let displayCurrency: Currency
    public let selectedRangeTotal: Money
    public let annualizedTotal: Money
    public let monthlyTotals: [SpendingMonthlyTotal]
    public let categoryTotals: [SpendingCategoryTotal]
    public let items: [SpendingInsightItem]

    public init(
        mode: SpendingReportMode,
        displayCurrency: Currency,
        selectedRangeTotal: Money,
        annualizedTotal: Money,
        monthlyTotals: [SpendingMonthlyTotal],
        categoryTotals: [SpendingCategoryTotal],
        items: [SpendingInsightItem]
    ) {
        self.mode = mode
        self.displayCurrency = displayCurrency
        self.selectedRangeTotal = selectedRangeTotal
        self.annualizedTotal = annualizedTotal
        self.monthlyTotals = monthlyTotals
        self.categoryTotals = categoryTotals
        self.items = items
    }
}

public enum SpendingInsightsState: Equatable, Sendable {
    case notLoaded
    case unavailable
    case available(SpendingInsights)

    public var availableValue: SpendingInsights? {
        guard case .available(let insights) = self else { return nil }
        return insights
    }
}
