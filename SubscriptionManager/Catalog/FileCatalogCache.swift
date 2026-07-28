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

@MainActor
final class FileExchangeRateCache: ExchangeRateCache {
    private let directory: URL
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL) {
        self.directory = directory
        fileURL = directory.appending(path: "exchange-rates.json")
    }

    func loadState() throws -> ExchangeRateCacheState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try decoder.decode(
            ExchangeRateCacheState.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func saveState(_ state: ExchangeRateCacheState) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
