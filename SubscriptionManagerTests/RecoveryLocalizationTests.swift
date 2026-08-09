import Foundation
import Testing

struct RecoveryLocalizationTests {
    @Test("Recovery UI strings include Simplified Chinese translations")
    func recoveryUIStringsIncludeSimplifiedChineseTranslations() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let catalogURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "SubscriptionManager/Resources/Localizable.xcstrings"
            )
        let data = try Data(contentsOf: catalogURL)
        let catalog = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try #require(catalog["strings"] as? [String: Any])
        let expectedTranslations = [
            "Couldn’t Load Setup Data": "无法加载设置数据",
            "Your library was not changed. Try loading it again.": "订阅库未被更改，请重新加载。",
            "Retry Calendar Sync": "重试同步日历",
        ]

        for (key, expectedTranslation) in expectedTranslations {
            let entry = try #require(strings[key] as? [String: Any])
            let localizations = try #require(
                entry["localizations"] as? [String: Any]
            )
            let simplifiedChinese = try #require(
                localizations["zh-Hans"] as? [String: Any]
            )
            let stringUnit = try #require(
                simplifiedChinese["stringUnit"] as? [String: Any]
            )

            #expect(stringUnit["value"] as? String == expectedTranslation)
        }
    }
}
