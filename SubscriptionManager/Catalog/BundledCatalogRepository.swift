import Foundation
import SubscriptionCore

@MainActor
final class BundledCatalogRepository: CatalogRepository {
    private let dataProvider: () throws -> Data

    init(
        bundle: Bundle = .main,
        resourceName: String = "catalog-v1"
    ) {
        dataProvider = {
            guard let resourceURL = bundle.url(
                forResource: resourceName,
                withExtension: "json"
            ) else {
                throw BundledCatalogRepositoryError.resourceNotFound
            }
            return try Data(contentsOf: resourceURL)
        }
    }

    init(resourceURL: URL) {
        dataProvider = { try Data(contentsOf: resourceURL) }
    }

    init(data: Data) {
        dataProvider = { data }
    }

    func loadSnapshot() throws -> CatalogSnapshot {
        try JSONDecoder().decode(
            CatalogSnapshot.self,
            from: dataProvider()
        )
    }
}

private enum BundledCatalogRepositoryError: Error {
    case resourceNotFound
}
