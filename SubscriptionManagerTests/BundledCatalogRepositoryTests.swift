import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct BundledCatalogRepositoryTests {
    @Test("Bundled catalog JSON decodes")
    @MainActor
    func bundledCatalogJSONDecodes() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()

        #expect(snapshot.catalogVersion == 12)
    }

    @Test("Bundled catalog has no empty offers")
    @MainActor
    func bundledCatalogHasNoEmptyOffers() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()

        #expect(snapshot.presets.allSatisfy { !$0.offers.isEmpty })
    }

    @Test("Bundled catalog groups the six AI services in one localized category")
    @MainActor
    func bundledCatalogGroupsAIServicesInOneCategory() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()
        let aiIDs: Set<String> = [
            "chatgpt", "claude", "google-ai", "doubao", "jimeng-ai",
            "iflytek-spark"
        ]

        let aiPresets = snapshot.presets.filter { aiIDs.contains($0.id) }
        #expect(Set(aiPresets.map(\.id)) == aiIDs)
        #expect(aiPresets.allSatisfy {
            $0.category.en == "AI" && $0.category.zhHans == "AI 工具"
        })
        #expect(snapshot.categories(locale: Locale(identifier: "zh-Hans")).contains {
            $0.id == "ai" && $0.title.en == "AI" && $0.title.zhHans == "AI 工具"
        })
    }

    @Test("Bundled catalog contains only verified offers with complete prices")
    @MainActor
    func bundledCatalogOffersAreVerifiedAndHaveCompletePrices() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()
        let offers = snapshot.presets.flatMap(\.offers)

        #expect(offers.count == 190)
        #expect(offers.allSatisfy { $0.reviewStatus == .verified })
        #expect(offers.allSatisfy { offer in
            offer.price.minorUnits > 0
                && !offer.price.currency.rawValue.isEmpty
                && !offer.billingInterval.rawValue.isEmpty
        })
    }

    @Test("Bundled catalog excludes retired empty presets")
    @MainActor
    func bundledCatalogExcludesRetiredEmptyPresets() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()
        let removedIDs: Set<String> = [
            "36kr", "aliyun", "cailianpress", "china-daily", "douyin", "dushu",
            "huawei-cloud", "huxiu", "jiemian", "qingcloud", "tencent-cloud",
            "the-paper", "upyun", "volcengine", "yuanfudao"
        ]

        #expect(snapshot.presets.allSatisfy { !removedIDs.contains($0.id) })
    }

    @Test("Bundled catalog pins representative official offers")
    @MainActor
    func bundledCatalogPinsRepresentativeOfficialOffers() throws {
        let snapshot = try BundledCatalogRepository().loadSnapshot()
        let offersByKey = Dictionary(
            uniqueKeysWithValues: snapshot.presets.flatMap { preset in
                preset.offers.map { ("\(preset.id)|\($0.id)", $0) }
            }
        )
        let expectedMinorUnits: [String: Int64] = [
            "taobao-88vip|88vip-shopping-card-cn-web": 8_800,
            "taobao-88vip|88vip-living-card-cn-web": 28_800,
            "jd-plus|jingdian-annual-cn-web": 9_900,
            "sams-club-china|ordinary-annual-cn-web": 26_000,
            "sams-club-china|premium-annual-cn-web": 68_000,
            "doubao|pro-advanced-monthly-cn-ios": 59_900,
            "doubao|pro-enhanced-yearly-cn-ios": 248_800,
            "jimeng-ai|jimeng-ai-member-monthly-cn-ios": 6_900,
            "jimeng-ai|jimeng-ai-member-yearly-cn-ios": 65_900,
            "jianying-pro|c-jianying-member-monthly-cn-ios": 2_500,
            "qq-music|a-qq-music-green-diamond-monthly-cn-ios": 1_500,
            "tencent-video|a-tencent-video-vip-monthly-cn-ios": 2_500,
            "baidu-netdisk|b-baidu-netdisk-svip-monthly-cn-ios": 2_500,
            "canva-china|c-canva-pro-monthly-cn-web": 3_000,
            "youtube-premium|youtube-premium-individual-monthly-us-web": 1_599,
            "youtube-premium|youtube-premium-family-monthly-us-web": 2_699,
            "youtube-premium|youtube-premium-student-monthly-us-web": 899,
            "youtube-premium|youtube-premium-lite-monthly-us-web": 899,
            "youtube-premium|youtube-premium-individual-yearly-us-web": 15_999
        ]

        for (key, expected) in expectedMinorUnits {
            let offer = try #require(offersByKey[key])
            #expect(offer.price.minorUnits == expected)
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

    @Test("A cached preset without a verified offer falls back to the bundle")
    @MainActor
    func unverifiedCachedCatalogFallsBackToBundledCatalog() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCatalogCache(directory: directory)
        let originalData = try #require(
            String(
                data: validCatalogData(catalogVersion: 2),
                encoding: .utf8
            )
        )
        #expect(originalData.contains("\"reviewStatus\": \"verified\""))
        let cachedData = originalData.replacingOccurrences(
            of: "\"reviewStatus\": \"verified\"",
            with: "\"reviewStatus\": \"reviewRequired\""
        )
        #expect(cachedData != originalData)
        #expect(
            cachedData.contains("\"reviewStatus\": \"reviewRequired\"")
        )
        try cache.storeCatalogData(Data(cachedData.utf8))
        let repository = CachedCatalogRepository(
            bundled: BundledCatalogRepository(data: validCatalogData()),
            cache: cache
        )

        let snapshot = try repository.loadSnapshot()

        #expect(snapshot.catalogVersion == 1)
        #expect(repository.catalogSource == .bundled)
    }

    @Test("A cached preset without offers falls back to the bundle")
    @MainActor
    func emptyOfferCachedCatalogFallsBackToBundledCatalog() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCatalogCache(directory: directory)
        let originalData = try #require(
            String(
                data: validCatalogData(catalogVersion: 2),
                encoding: .utf8
            )
        )
        #expect(originalData.contains("\"offers\": ["))
        let cachedData = originalData.replacingOccurrences(
            of: "\"offers\": [",
            with: "\"offers\": [], \"ignoredOffers\": ["
        )
        #expect(cachedData != originalData)
        #expect(cachedData.contains("\"offers\": []"))
        try cache.storeCatalogData(Data(cachedData.utf8))
        let repository = CachedCatalogRepository(
            bundled: BundledCatalogRepository(data: validCatalogData()),
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

        #expect(snapshot.presets.count == 93)
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
          "assetProvenance": { "kind": "originalSymbol", "license": "CC0-1.0", "source": "\(presetID)" },
          "offers": [
            {
              "id": "monthly",
              "planName": { "en": "Monthly", "zhHans": "月付" },
              "price": { "minorUnits": 100, "currency": "CNY" },
              "billingInterval": "monthly",
              "market": "CN",
              "purchaseChannel": "web",
              "sourceURL": "https://example.com/pricing",
              "verifiedOn": "2026-08-09",
              "reviewStatus": "verified"
            }
          ]
        }
      ]
    }
    """.utf8)
}
