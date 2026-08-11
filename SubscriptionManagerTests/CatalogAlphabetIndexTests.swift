import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct CatalogAlphabetIndexTests {
    @Test("Cancelled catalog index highlights cannot expire newer selections")
    func cancelledHighlightExpirationDoesNotComplete() async {
        let expiration = Task {
            await CatalogIndexHighlightExpiration.wait(for: .seconds(30))
        }

        expiration.cancel()

        #expect(await expiration.value == false)
    }

    @Test("Completed catalog index highlights may expire")
    func completedHighlightExpirationCompletes() async {
        #expect(
            await CatalogIndexHighlightExpiration.wait(for: .zero)
        )
    }

    @Test("Catalog index groups localized names by represented initial")
    func groupsLocalizedNames() {
        let sections = CatalogIndexProjection.sections(
            for: [
                preset(id: "b", en: "Baidu Netdisk", zhHans: "百度网盘"),
                preset(id: "a", en: "Apple Music", zhHans: "Apple Music"),
                preset(id: "symbol", en: "123 Cloud", zhHans: "123 云盘"),
            ],
            locale: Locale(identifier: "en")
        )

        #expect(sections.map(\.id) == ["A", "B", "#"])
        #expect(sections[1].presets.map(\.id) == ["b"])
    }

    @Test("Simplified Chinese catalog names use Mandarin initials")
    func transliteratesChineseNames() {
        let sections = CatalogIndexProjection.sections(
            for: [
                preset(id: "zhihu", en: "Zhihu", zhHans: "知乎"),
                preset(id: "baidu", en: "Baidu", zhHans: "百度网盘"),
            ],
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(sections.map(\.id) == ["B", "Z"])
        #expect(sections[0].presets.map(\.id) == ["baidu"])
    }

    @Test("Catalog index sorts names within each localized section")
    func sortsNamesWithinSections() {
        let sections = CatalogIndexProjection.sections(
            for: [
                preset(id: "zulu", en: "Zulu", zhHans: "Zulu"),
                preset(id: "alpha", en: "Alpha", zhHans: "Alpha"),
                preset(id: "azure", en: "Azure", zhHans: "Azure"),
            ],
            locale: Locale(identifier: "en")
        )

        #expect(sections.map(\.id) == ["A", "Z"])
        #expect(sections[0].presets.map(\.id) == ["alpha", "azure"])
    }
}

private func preset(
    id: String,
    en: String,
    zhHans: String
) -> CatalogPreset {
    CatalogPreset(
        id: id,
        serviceName: CatalogLocalizedText(en: en, zhHans: zhHans),
        category: CatalogLocalizedText(
            en: "Productivity",
            zhHans: "效率"
        ),
        suggestedInterval: .monthly,
        managementURL: nil,
        icon: .productivity
    )
}
