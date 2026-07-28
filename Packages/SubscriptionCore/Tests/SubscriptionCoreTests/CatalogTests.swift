import Foundation
import SubscriptionCore
import Testing

@Suite("Bundled catalog domain")
struct CatalogTests {
    @Test("Catalog search uses localized service and category text")
    func localizedSearchUsesServiceAndCategory() throws {
        let music = CatalogPreset(
            id: "music.example",
            serviceName: CatalogLocalizedText(
                en: "Example Music",
                zhHans: "示例音乐"
            ),
            category: CatalogLocalizedText(
                en: "Music",
                zhHans: "音乐"
            ),
            suggestedInterval: .monthly,
            managementURL: URL(string: "https://example.com/manage"),
            icon: .music
        )
        let snapshot = try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            presets: [music]
        )

        #expect(
            snapshot.search(
                query: "音乐",
                locale: Locale(identifier: "zh-Hans")
            ) == [music]
        )
        #expect(
            snapshot.search(
                query: "music",
                locale: Locale(identifier: "en")
            ) == [music]
        )
    }

    @Test("Catalog snapshot rejects duplicate stable identifiers")
    func catalogSnapshotRejectsDuplicateIdentifiers() {
        let preset = CatalogPreset(
            id: "duplicate.example",
            serviceName: CatalogLocalizedText(en: "Duplicate", zhHans: "重复"),
            category: CatalogLocalizedText(en: "Other", zhHans: "其他"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .other
        )

        #expect(throws: CatalogLoadError.self) {
            try CatalogSnapshot(
                schemaVersion: CatalogSnapshot.currentSchemaVersion,
                presets: [preset, preset]
            )
        }
    }
}
