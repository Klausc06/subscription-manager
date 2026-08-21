import Foundation
import Testing

struct RecoveryLocalizationTests {
    @Test("Recovery UI strings include Simplified Chinese translations")
    func recoveryUIStringsIncludeSimplifiedChineseTranslations() throws {
        let localizationURL = try #require(
            Bundle.main.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: "zh-Hans"
            )
        )
        let data = try Data(contentsOf: localizationURL)
        let strings = try #require(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: String]
        )
        let expectedTranslations = [
            "Couldn’t Load Setup Data": "无法加载设置数据",
            "Your library was not changed. Try loading it again.": "订阅库未被更改，请重新加载。",
            "Retry Calendar Sync": "重试同步日历",
            "Calendar sync is unavailable. Check Calendar access and try again.": "日历同步不可用。请检查日历访问权限，然后重试。",
        ]

        for (key, expectedTranslation) in expectedTranslations {
            #expect(strings[key] == expectedTranslation)
        }
    }
}
