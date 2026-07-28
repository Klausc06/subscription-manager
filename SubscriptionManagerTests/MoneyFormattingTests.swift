import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("Money text parser")
struct MoneyFormattingTests {
    @Test("Trailing non-numeric text is rejected")
    func trailingNonNumericTextIsRejected() {
        let money = MoneyTextParser.parse(
            "12.34abc",
            currency: .cny,
            locale: Locale(identifier: "en_US")
        )

        #expect(money == nil)
    }

    @Test("Leading and trailing whitespace is ignored")
    func surroundingWhitespaceIsIgnored() {
        let money = MoneyTextParser.parse(
            " \n12.34\t ",
            currency: .usd,
            locale: Locale(identifier: "en_US")
        )

        #expect(money == Money(minorUnits: 1_234, currency: .usd))
    }

    @Test("A decimal point produces exact minor units in English")
    func englishDecimalPointProducesExactMinorUnits() {
        let money = MoneyTextParser.parse(
            "12.34",
            currency: .cny,
            locale: Locale(identifier: "en_US")
        )

        #expect(money == Money(minorUnits: 1_234, currency: .cny))
    }

    @Test("A decimal point produces exact minor units in Simplified Chinese")
    func simplifiedChineseDecimalPointProducesExactMinorUnits() {
        let money = MoneyTextParser.parse(
            "12.34",
            currency: .usd,
            locale: Locale(identifier: "zh_CN")
        )

        #expect(money == Money(minorUnits: 1_234, currency: .usd))
    }

    @Test("More than two fractional digits are rejected")
    func moreThanTwoFractionalDigitsAreRejected() {
        let money = MoneyTextParser.parse(
            "12.345",
            currency: .cny,
            locale: Locale(identifier: "en_US")
        )

        #expect(money == nil)
    }

    @Test("The largest representable amount remains exact")
    func largestRepresentableAmountRemainsExact() {
        let money = MoneyTextParser.parse(
            "92233720368547758.07",
            currency: .cny,
            locale: Locale(identifier: "en_US")
        )

        #expect(money == Money(
            minorUnits: Int64.max,
            currency: .cny
        ))
    }

    @Test("Amounts beyond Int64 minor units are rejected")
    func amountBeyondMinorUnitRangeIsRejected() {
        let money = MoneyTextParser.parse(
            "92233720368547758.08",
            currency: .usd,
            locale: Locale(identifier: "en_US")
        )

        #expect(money == nil)
    }

    @Test("Editable money round-trips in a comma-decimal locale")
    func editableMoneyRoundTripsInCommaDecimalLocale() {
        let locale = Locale(identifier: "de_DE")
        let money = Money(minorUnits: 1_234, currency: .usd)

        let text = editableMoneyText(money, locale: locale)

        #expect(text == "12,34")
        #expect(
            MoneyTextParser.parse(
                text,
                currency: money.currency,
                locale: locale
            ) == money
        )
    }

    @Test("Date-only billing input is normalized to local noon")
    func billingDateIsNormalizedToLocalNoon() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let input = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2025,
                    month: 3,
                    day: 9,
                    hour: 1,
                    minute: 37
                )
            )
        )

        let normalized = try #require(
            normalizedBillingDate(
                input,
                timeZoneIdentifier: "America/Los_Angeles"
            )
        )

        #expect(
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: normalized
            ) == DateComponents(
                year: 2025,
                month: 3,
                day: 9,
                hour: 12,
                minute: 0
            )
        )
    }

    @Test("Billing dates render in the stored schedule time zone")
    func billingDateFormattingUsesStoredTimeZone() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = try #require(
            utc.date(
                from: DateComponents(
                    year: 2025,
                    month: 2,
                    day: 28,
                    hour: 16,
                    minute: 30
                )
            )
        )
        let locale = Locale(identifier: "en_US")

        #expect(
            formattedBillingDate(
                date,
                timeZoneIdentifier: "Asia/Shanghai",
                locale: locale
            ) == "Mar 1, 2025"
        )
        #expect(
            formattedBillingDate(
                date,
                timeZoneIdentifier: "America/Los_Angeles",
                locale: locale
            ) == "Feb 28, 2025"
        )
    }
}
