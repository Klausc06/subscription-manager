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

@MainActor
final class CachedCatalogRepository: CatalogRepository {
    private let bundled: BundledCatalogRepository
    private let cache: FileCatalogCache

    private(set) var catalogSource: CatalogSource = .bundled

    init(bundled: BundledCatalogRepository, cache: FileCatalogCache) {
        self.bundled = bundled
        self.cache = cache
    }

    func loadSnapshot() throws -> CatalogSnapshot {
        do {
            if let data = try cache.loadCatalogData() {
                let snapshot = try JSONDecoder().decode(
                    CatalogSnapshot.self,
                    from: data
                )
                catalogSource = .cached
                return snapshot
            }
        } catch {
            // A corrupt cache is never allowed to prevent offline browsing.
        }

        catalogSource = .bundled
        return try bundled.loadSnapshot()
    }
}

private enum BundledCatalogRepositoryError: Error {
    case resourceNotFound
}
