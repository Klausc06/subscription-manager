import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct BundledCatalogRepositoryTests {
    @Test("Bundled catalog exposes verified first-batch offers")
    @MainActor
    func bundledCatalogExposesVerifiedFirstBatchOffers() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()
        #expect(snapshot.catalogVersion == 5)
        #expect(snapshot.presets.count == 106)

        let chatGPT = try #require(
            snapshot.presets.first(where: { $0.id == "chatgpt" })
        )
        #expect(chatGPT.serviceName.en == "ChatGPT")
        #expect(chatGPT.matchAliases == ["ChatGPT Plus"])
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
                #expect(offer.purchaseChannel == .web)
                #expect(offer.reviewStatus == .verified)
                #expect(offer.sourceURL.scheme == "https")
                #expect(offer.verifiedOn == "2026-07-30")
            }
        }
    }

    @Test("Bundled catalog pins the exact verified offer table")
    @MainActor
    func bundledCatalogPinsExactVerifiedOfferTable() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()

        let actualOffers = snapshot.presets.flatMap { preset in
            preset.offers.map { offer in
                [
                    preset.id,
                    offer.id,
                    offer.planName.en,
                    offer.planName.zhHans,
                    offer.billingInterval.rawValue,
                    String(offer.price.minorUnits),
                    offer.sourceURL.absoluteString
                ].joined(separator: "|")
            }
        }

        #expect(actualOffers == expectedVerifiedOfferTable)
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

    @Test("An older cache never overrides a newer bundled catalog")
    @MainActor
    func olderCacheDoesNotOverrideNewerBundle() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCatalogCache(directory: directory)
        try cache.storeCatalogData(
            validCatalogData(catalogVersion: 3, presetID: "cached")
        )
        let repository = CachedCatalogRepository(
            bundled: BundledCatalogRepository(
                data: validCatalogData(
                    catalogVersion: 4,
                    presetID: "bundled"
                )
            ),
            cache: cache
        )

        let snapshot = try repository.loadSnapshot()

        #expect(snapshot.catalogVersion == 4)
        #expect(snapshot.presets.map(\.id) == ["bundled"])
        #expect(repository.catalogSource == .bundled)
    }

    @Test("A newer cache overrides the bundled catalog")
    @MainActor
    func newerCacheOverridesBundle() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCatalogCache(directory: directory)
        try cache.storeCatalogData(
            validCatalogData(catalogVersion: 5, presetID: "cached")
        )
        let repository = CachedCatalogRepository(
            bundled: BundledCatalogRepository(
                data: validCatalogData(
                    catalogVersion: 4,
                    presetID: "bundled"
                )
            ),
            cache: cache
        )

        let snapshot = try repository.loadSnapshot()

        #expect(snapshot.catalogVersion == 5)
        #expect(snapshot.presets.map(\.id) == ["cached"])
        #expect(repository.catalogSource == .cached)
    }

    @Test("A same-version cache defers to the trusted bundle")
    @MainActor
    func sameVersionCacheDefersToBundle() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCatalogCache(directory: directory)
        try cache.storeCatalogData(
            validCatalogData(catalogVersion: 4, presetID: "cached")
        )
        let repository = CachedCatalogRepository(
            bundled: BundledCatalogRepository(
                data: validCatalogData(
                    catalogVersion: 4,
                    presetID: "bundled"
                )
            ),
            cache: cache
        )

        let snapshot = try repository.loadSnapshot()

        #expect(snapshot.catalogVersion == 4)
        #expect(snapshot.presets.map(\.id) == ["bundled"])
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

private let expectedVerifiedOfferTable = [
    "spotify|individual-monthly-us-web|Individual|Individual|monthly|1299|https://www.spotify.com/us/premium/",
    "spotify|student-monthly-us-web|Student|Student|monthly|699|https://www.spotify.com/us/premium/",
    "spotify|duo-monthly-us-web|Duo|Duo|monthly|1899|https://www.spotify.com/us/premium/",
    "spotify|family-monthly-us-web|Family|Family|monthly|2199|https://www.spotify.com/us/premium/",
    "netflix|ads-monthly-us-web|Standard with ads|Standard with ads|monthly|899|https://help.netflix.com/en/node/22",
    "netflix|standard-monthly-us-web|Standard|Standard|monthly|1999|https://help.netflix.com/en/node/22",
    "netflix|premium-monthly-us-web|Premium|Premium|monthly|2699|https://help.netflix.com/en/node/22",
    "notion|plus-one-member-monthly-us-web|Plus (1 member)|Plus (1 member)|monthly|1200|https://www.notion.com/pricing",
    "notion|plus-one-member-yearly-us-web|Plus (1 member)|Plus (1 member)|yearly|12000|https://www.notion.com/pricing",
    "chatgpt|go-monthly-us-web|Go|Go|monthly|800|https://openai.com/chatgpt/pricing/",
    "chatgpt|plus-monthly-us-web|Plus|Plus|monthly|2000|https://openai.com/chatgpt/pricing/",
    "chatgpt|pro-5x-monthly-us-web|Pro (5x)|Pro（5x）|monthly|10000|https://help.openai.com/en/articles/9793128-what-is-chatgpt-pro",
    "chatgpt|pro-20x-monthly-us-web|Pro (20x)|Pro（20x）|monthly|20000|https://help.openai.com/en/articles/9793128-what-is-chatgpt-pro",
    "claude|pro-monthly-us-web|Pro|Pro|monthly|2000|https://www.anthropic.com/pricing",
    "claude|pro-yearly-us-web|Pro|Pro|yearly|20000|https://www.anthropic.com/pricing",
    "claude|max-5x-monthly-us-web|Max (5x)|Max (5x)|monthly|10000|https://www.anthropic.com/pricing",
    "claude|max-20x-monthly-us-web|Max (20x)|Max (20x)|monthly|20000|https://www.anthropic.com/pricing",
    "google-ai|ai-plus-monthly-us-web|Google AI Plus|Google AI Plus|monthly|999|https://one.google.com/about/google-ai-plans/",
    "google-ai|ai-pro-monthly-us-web|Google AI Pro|Google AI Pro|monthly|1999|https://one.google.com/about/google-ai-plans/",
    "microsoft-365|personal-monthly-us-web|Personal|Personal|monthly|999|https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365",
    "microsoft-365|personal-yearly-us-web|Personal|Personal|yearly|9999|https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365",
    "microsoft-365|family-monthly-us-web|Family|Family|monthly|1299|https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365",
    "microsoft-365|family-yearly-us-web|Family|Family|yearly|12999|https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365",
    "microsoft-365|premium-monthly-us-web|Premium|Premium|monthly|1999|https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365",
    "microsoft-365|premium-yearly-us-web|Premium|Premium|yearly|19999|https://www.microsoft.com/en-us/microsoft-365/buy/microsoft-365",
    "youtube-premium|lite-monthly-us-web|Premium Lite|Premium Lite|monthly|799|https://blog.youtube/news-and-events/introducing-premium-lite/",
    "disney-plus|ads-monthly-us-web|With Ads|With Ads|monthly|1199|https://help.disneyplus.com/article/disneyplus-price",
    "disney-plus|premium-monthly-us-web|Premium|Premium|monthly|1899|https://help.disneyplus.com/article/disneyplus-price",
    "disney-plus|premium-yearly-us-web|Premium|Premium|yearly|18999|https://help.disneyplus.com/article/disneyplus-price",
    "canva|pro-one-person-yearly-us-web|Pro (1 person)|Pro (1 person)|yearly|18000|https://www.canva.com/pricing/"
]

private func validCatalogData(
    catalogVersion: Int = 1,
    presetID: String = "music.example"
) -> Data {
    Data("""
    {
      "schemaVersion": 1,
      "catalogVersion": \(catalogVersion),
      "presets": [
        {
          "id": "\(presetID)",
          "serviceName": { "en": "Music", "zhHans": "音乐" },
          "category": { "en": "Music", "zhHans": "音乐" },
          "suggestedInterval": "monthly",
          "managementURL": null,
          "icon": "music",
          "assetProvenance": { "kind": "originalSymbol", "license": "CC0-1.0", "source": "\(presetID)" }
        }
      ]
    }
    """.utf8)
}
