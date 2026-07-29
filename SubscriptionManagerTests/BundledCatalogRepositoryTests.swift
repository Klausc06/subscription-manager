import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct BundledCatalogRepositoryTests {
    @Test("Bundled catalog exposes verified first-batch offers")
    @MainActor
    func bundledCatalogExposesVerifiedFirstBatchOffers() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()
        #expect(snapshot.catalogVersion == 4)
        #expect(snapshot.presets.count == 106)

        let chatGPT = try #require(
            snapshot.presets.first(where: { $0.id == "chatgpt" })
        )
        #expect(chatGPT.serviceName.en == "ChatGPT")
        #expect(chatGPT.offers.map(\.id) == [
            "go-monthly-us-web",
            "plus-monthly-us-web",
            "pro-5x-monthly-us-web",
            "pro-20x-monthly-us-web"
        ])
        #expect(
            chatGPT.offers.map(\.price.minorUnits)
                == [800, 2_000, 10_000, 20_000]
        )
        #expect(chatGPT.offers.allSatisfy {
            $0.billingInterval == .monthly
        })
        #expect(
            snapshot.presets.contains(where: { $0.id == "chatgpt-plus" })
                == false
        )

        for preset in snapshot.presets {
            for offer in preset.offers {
                #expect(offer.price.currency == .usd)
                #expect(offer.market == "US")
                #expect(offer.reviewStatus == .verified)
                #expect(offer.sourceURL.scheme == "https")
                #expect(offer.verifiedOn == "2026-07-30")
            }
        }
    }

    @Test("Catalog cache atomically replaces data after it is validated")
    @MainActor
    func catalogCacheStoresReplacementData() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCatalogCache(directory: directory)
        let data = Data("{\"catalogVersion\":2}".utf8)

        try cache.storeCatalogData(data)

        #expect(try cache.loadCatalogData() == data)
    }

    @Test("Invalid cached catalog falls back to the bundled catalog")
    @MainActor
    func invalidCachedCatalogFallsBackToBundledCatalog() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCatalogCache(directory: directory)
        try cache.storeCatalogData(Data("invalid".utf8))
        let bundled = BundledCatalogRepository(data: validCatalogData())
        let repository = CachedCatalogRepository(
            bundled: bundled,
            cache: cache
        )

        let snapshot = try repository.loadSnapshot()

        #expect(snapshot.catalogVersion == 1)
        #expect(repository.catalogSource == .bundled)
    }

    @Test("The bundled catalog decodes and exposes localized presets")
    @MainActor
    func bundledCatalogIsValid() throws {
        let resourceURL = try #require(
            Bundle.main.url(forResource: "catalog-v1", withExtension: "json")
        )
        let repository = BundledCatalogRepository(resourceURL: resourceURL)

        let snapshot = try repository.loadSnapshot()

        #expect(snapshot.presets.count == 106)
        #expect(
            snapshot.search(query: "音乐", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "spotify" })
        )
        #expect(
            snapshot.search(query: "哔哩哔哩", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "bilibili" })
        )
        #expect(
            snapshot.search(query: "Bilibili", locale: Locale(identifier: "en"))
                .contains(where: { $0.id == "bilibili" })
        )
        #expect(
            snapshot.search(query: "网易云音乐", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "netease-cloud-music" })
        )
        #expect(
            snapshot.search(query: "起点读书", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "qidian" })
        )
        #expect(
            snapshot.search(query: "财新", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "caixin" })
        )
        #expect(
            snapshot.search(query: "Tencent START", locale: Locale(identifier: "en"))
                .contains(where: { $0.id == "tencent-start" })
        )
        #expect(
            snapshot.search(query: "WPS 会员", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "wps-office" })
        )
        #expect(
            snapshot.search(query: "Baidu Netdisk", locale: Locale(identifier: "en"))
                .contains(where: { $0.id == "baidu-netdisk" })
        )
        #expect(
            snapshot.search(query: "飞书", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "feishu" })
        )
        #expect(
            snapshot.search(query: "Youdao Premium", locale: Locale(identifier: "en"))
                .contains(where: { $0.id == "youdao-premium" })
        )
        #expect(
            snapshot.search(query: "京东 PLUS", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "jd-plus" })
        )
    }

    @Test("Malformed bundled catalog identifiers are rejected")
    @MainActor
    func malformedCatalogIdentifiersAreRejected() throws {
        let repository = BundledCatalogRepository(data: Data("""
        {
          "schemaVersion": 1,
          "presets": [
            {
              "id": " ",
              "serviceName": { "en": "One", "zhHans": "一" },
              "category": { "en": "Music", "zhHans": "音乐" },
              "suggestedInterval": "monthly",
              "managementURL": null,
              "icon": "music"
            }
          ]
        }
        """.utf8))

        #expect(throws: (any Error).self) {
            try repository.loadSnapshot()
        }
    }

    @Test("Bundled catalog entries require both localized names")
    @MainActor
    func bundledCatalogRequiresLocalizedNames() throws {
        let repository = BundledCatalogRepository(data: Data("""
        {
          "schemaVersion": 1,
          "presets": [
            {
              "id": "missing-localized-name",
              "serviceName": { "en": "", "zhHans": "示例" },
              "category": { "en": "Music", "zhHans": "音乐" },
              "suggestedInterval": "monthly",
              "managementURL": null,
              "icon": "music"
            }
          ]
        }
        """.utf8))

        #expect(throws: (any Error).self) {
            try repository.loadSnapshot()
        }
    }
}

private func validCatalogData() -> Data {
    Data("""
    {
      "schemaVersion": 1,
      "catalogVersion": 1,
      "presets": [
        {
          "id": "music.example",
          "serviceName": { "en": "Music", "zhHans": "音乐" },
          "category": { "en": "Music", "zhHans": "音乐" },
          "suggestedInterval": "monthly",
          "managementURL": null,
          "icon": "music",
          "assetProvenance": { "kind": "originalSymbol", "license": "CC0-1.0", "source": "music.example" }
        }
      ]
    }
    """.utf8)
}
