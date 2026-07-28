import Foundation
import SubscriptionCore

@MainActor
final class FileCatalogCache: CatalogCache {
    private let directory: URL
    private let fileURL: URL

    init(directory: URL) {
        self.directory = directory
        fileURL = directory.appending(path: "catalog-cache.json")
    }

    func loadCatalogData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    func storeCatalogData(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
