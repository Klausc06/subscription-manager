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
