import Foundation
import Testing
@Suite("Renewal countdown localization")
struct RenewalCountdownLocalizationTests {
    /// The key carries two `%lld` positions, so its English plural has to come
    /// from an explicit substitution bound to argument 1. A top-level plural
    /// variation compiles with a warning and cannot say which argument it
    /// agrees with, so these assertions pin the rendered result rather than the
    /// catalog shape.
    @Test("The English countdown agrees with the day count")
    func englishCountdownAgreesWithDayCount() throws {
        #expect(
            try renderedCountdown(days: 1, percent: 50, language: "en")
                == "1 day until renewal, 50 percent elapsed"
        )
        #expect(
            try renderedCountdown(days: 2, percent: 50, language: "en")
                == "2 days until renewal, 50 percent elapsed"
        )
        #expect(
            try renderedCountdown(days: 0, percent: 100, language: "en")
                == "0 days until renewal, 100 percent elapsed"
        )
    }

    @Test("The Simplified Chinese countdown keeps both positional arguments")
    func simplifiedChineseCountdownKeepsPositionalArguments() throws {
        #expect(
            try renderedCountdown(days: 1, percent: 50, language: "zh-Hans")
                == "距下次续订还有 1 天，本期已过 50%"
        )
        #expect(
            try renderedCountdown(days: 2, percent: 75, language: "zh-Hans")
                == "距下次续订还有 2 天，本期已过 75%"
        )
    }

    /// `locale:` alone only drives formatting; the localization comes from the
    /// bundle. Resolving each language's `.lproj` keeps the assertions
    /// independent of whatever preferred language the test process runs under.
    private func renderedCountdown(
        days: Int,
        percent: Int,
        language: String
    ) throws -> String {
        let url = try #require(
            Bundle.main.url(forResource: language, withExtension: "lproj")
        )
        let bundle = try #require(Bundle(url: url))
        return String(
            localized: "\(days) days until renewal, \(percent) percent elapsed",
            bundle: bundle,
            locale: Locale(identifier: language)
        )
    }
}
