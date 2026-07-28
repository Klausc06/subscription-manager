import Foundation
import SubscriptionCore

@MainActor
final class GitHubCatalogUpdateSource: CatalogUpdateSource {
    static let catalogURL = URL(
        string: "https://raw.githubusercontent.com/Klausc06/subscription-manager/main/SubscriptionManager/Resources/catalog-v1.json"
    )!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCatalogData() async throws -> Data {
        let (data, response) = try await session.data(from: Self.catalogURL)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200
        else {
            throw GitHubCatalogUpdateError.invalidResponse
        }
        return data
    }
}

private enum GitHubCatalogUpdateError: Error {
    case invalidResponse
}

@MainActor
final class FrankfurterExchangeRateSource: ExchangeRateSource {
    static let ratesURL = URL(string: "https://api.frankfurter.dev/v2/rates")!

    private let session: URLSession
    private let now: () -> Date

    init(
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.now = now
    }

    func fetchRates(
        base: Currency,
        quotes: Set<Currency>
    ) async throws -> ExchangeRateSnapshot {
        let fetchedAt = now()
        guard !quotes.isEmpty else {
            return ExchangeRateSnapshot(
                base: base,
                providerDate: fetchedAt,
                fetchedAt: fetchedAt,
                source: "Frankfurter v2",
                rates: [base: 1]
            )
        }
        let url = Self.ratesURL.appending(queryItems: [
            URLQueryItem(name: "base", value: base.rawValue),
            URLQueryItem(
                name: "quotes",
                value: quotes.map(\.rawValue).sorted().joined(separator: ",")
            ),
        ])
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200
        else {
            throw FrankfurterExchangeRateError.invalidResponse
        }
        return try Self.decodeSnapshot(
            data: data,
            base: base,
            quotes: quotes,
            fetchedAt: fetchedAt
        )
    }

    static func decodeSnapshot(
        data: Data,
        base: Currency,
        quotes: Set<Currency>,
        fetchedAt: Date
    ) throws -> ExchangeRateSnapshot {
        let rates = try JSONDecoder().decode([FrankfurterRate].self, from: data)
        var parsedRates: [Currency: Decimal] = [base: 1]
        var providerDate: Date?
        for rate in rates {
            guard rate.base == base.rawValue,
                  let quote = Currency(rawValue: rate.quote),
                  quotes.contains(quote),
                  rate.rate > 0,
                  let parsedDate = Self.dateFormatter.date(from: rate.date)
            else {
                throw FrankfurterExchangeRateError.invalidPayload
            }
            if let providerDate, providerDate != parsedDate {
                throw FrankfurterExchangeRateError.invalidPayload
            }
            providerDate = parsedDate
            guard parsedRates[quote] == nil else {
                throw FrankfurterExchangeRateError.invalidPayload
            }
            parsedRates[quote] = rate.rate
        }
        guard Set(parsedRates.keys).subtracting([base]) == quotes,
              let providerDate
        else {
            throw FrankfurterExchangeRateError.invalidPayload
        }
        return ExchangeRateSnapshot(
            base: base,
            providerDate: providerDate,
            fetchedAt: fetchedAt,
            source: "Frankfurter v2",
            rates: parsedRates
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct FrankfurterRate: Decodable {
    let date: String
    let base: String
    let quote: String
    let rate: Decimal
}

private enum FrankfurterExchangeRateError: Error {
    case invalidPayload
    case invalidResponse
}
