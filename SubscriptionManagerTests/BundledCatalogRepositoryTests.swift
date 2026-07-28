import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct BundledCatalogRepositoryTests {
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

        #expect(snapshot.presets.count >= 8)
        #expect(
            snapshot.search(query: "音乐", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "spotify" })
        )
    }

    @Test("China batch A is complete, categorized, and bilingual-searchable")
    @MainActor
    func chinaBatchAIsDiscoverable() throws {
        let resourceURL = try #require(
            Bundle.main.url(forResource: "catalog-v1", withExtension: "json")
        )
        let snapshot = try BundledCatalogRepository(resourceURL: resourceURL)
            .loadSnapshot()
        let chinaBatchAIDs: Set<String> = [
            "iqiyi-vip", "tencent-video-vip", "youku-vip", "mango-tv-vip",
            "bilibili-premium", "migu-video-vip", "sohu-video-vip", "pptv-vip",
            "jianying-vip", "kling-ai-membership",
            "qq-music-vip", "netease-cloud-music-vip", "kugou-music-vip",
            "kuwo-music-vip", "migu-music-vip", "ximalaya-vip", "qingting-fm-vip",
            "lizhi-fm-vip", "kugou-concept-vip", "qq-audiobook-vip",
            "wechat-reading-unlimited", "qq-reading-vip", "qidian-reading-vip",
            "zongheng-reading-vip", "fanqie-reading-vip", "jd-reading-vip",
            "duokan-reading-vip", "jinjiang-reading-vip", "zhuishushenqi-vip",
            "caixin-digital", "36kr-pro", "huxiu-plus", "yicai-plus",
            "jiemian-premium", "the-paper-membership", "southern-weekly-digital",
            "china-daily-digital", "guancha-membership",
            "genshin-impact-welkin", "honkai-star-rail-supply-pass",
            "zenless-zone-zero-membership", "honkai-impact-3-monthly-card",
            "arknights-monthly-card", "identity-v-monthly-card",
            "onmyoji-monthly-card", "naraka-bladepoint-pass", "taptap-cloud-gaming"
        ]

        #expect(snapshot.catalogVersion == 2)
        #expect(chinaBatchAIDs.count == 47)
        #expect(
            Set(snapshot.presets.map(\.id)).isSuperset(of: chinaBatchAIDs)
        )
        #expect(
            Set(snapshot.presets.map { $0.category.en }).isSuperset(
                of: ["Video", "Music", "Reading", "News", "Gaming"]
            )
        )
        #expect(
            snapshot.search(query: "腾讯视频", locale: Locale(identifier: "zh-Hans"))
                .contains(where: { $0.id == "tencent-video-vip" })
        )
        #expect(
            snapshot.search(query: "Genshin", locale: Locale(identifier: "en"))
                .contains(where: { $0.id == "genshin-impact-welkin" })
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
