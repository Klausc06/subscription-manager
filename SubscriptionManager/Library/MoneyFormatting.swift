import Foundation
import SubscriptionCore

func formattedMoney(_ money: Money) -> String {
    let decimalAmount = Decimal(money.minorUnits) / 100
    return decimalAmount.formatted(
        .currency(code: money.currency.rawValue)
    )
}

enum MoneyTextParser {
    static func parse(
        _ text: String,
        currency: Currency,
        locale: Locale
    ) -> Money? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: value)
        scanner.locale = locale
        guard !value.isEmpty,
              let decimal = scanner.scanDecimal(),
              scanner.isAtEnd,
              decimal > 0
        else {
            return nil
        }

        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)

        guard rounded == scaled,
              rounded <= Decimal(Int64.max)
        else {
            return nil
        }

        return Money(
            minorUnits: NSDecimalNumber(decimal: rounded).int64Value,
            currency: currency
        )
    }
}
