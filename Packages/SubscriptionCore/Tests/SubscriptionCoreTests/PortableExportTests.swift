import Foundation
import Testing
@testable import SubscriptionCore

@Suite("Portable exports")
struct PortableExportTests {
    @Test("A versioned backup round trips stable subscription and preference data")
    func backupRoundTrips() throws {
        let subscription = Subscription(
            id: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!,
            serviceIdentity: ServiceIdentity(rawValue: "atlas"),
            serviceName: "Atlas, 国际版",
            plan: "Pro\nAnnual",
            category: "Productivity",
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            billingCycle: .yearly,
            startDate: Date(timeIntervalSince1970: 1_704_067_200),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_735_689_600),
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: "A \"quoted\" note",
            confirmedCharges: [
                ConfirmedCharge(
                    id: UUID(uuidString: "99999999-2222-3333-4444-555555555556")!,
                    chargedDate: Date(timeIntervalSince1970: 1_704_067_200),
                    amount: Money(minorUnits: 1_299, currency: .usd)
                )
            ],
            priceChanges: [
                PriceChange(
                    id: UUID(uuidString: "99999999-2222-3333-4444-555555555557")!,
                    effectiveDate: Date(timeIntervalSince1970: 1_735_689_600),
                    amount: Money(minorUnits: 1_499, currency: .usd)
                )
            ],
            lifecycle: .active,
            isArchived: true
        )
        let backup = PortableBackup(
            preferences: UserPreferences(
                primaryCurrency: .cny,
                calendarProjectionHorizon: .sixMonths,
                hideAmountsInCalendar: true,
                setupStatus: .completed
            ),
            subscriptions: [subscription]
        )

        let data = try PortableBackupEncoder().encode(backup)
        let decoded = try PortableBackupEncoder().decode(data)

        #expect(decoded == backup)
        #expect(decoded.schemaVersion == 1)
    }

    @Test("CSV quotes Unicode commas quotes and line breaks with machine money")
    func csvEscapesMachineReadableFields() throws {
        let subscription = Subscription(
            id: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!,
            serviceIdentity: ServiceIdentity(rawValue: "atlas"),
            serviceName: "Atlas, 国际版",
            plan: "Pro\nAnnual",
            category: "Productivity",
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            billingCycle: .yearly,
            startDate: Date(timeIntervalSince1970: 1_704_067_200),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_735_689_600),
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: "A \"quoted\" note",
            isArchived: true
        )

        let data = PortableCSVEncoder().encode(
            preferences: .default,
            subscriptions: [subscription]
        )
        let rows = try CSVFixtureParser().parse(data)

        #expect(rows.count == 2)
        #expect(rows[0][0] == "subscription_id")
        #expect(rows[1][1] == "Atlas, 国际版")
        #expect(rows[1][2] == "Pro\nAnnual")
        #expect(rows[1][6] == "1299")
        #expect(rows[1][7] == "USD")
        #expect(rows[1][11].isEmpty)
        #expect(rows[1][12] == "A \"quoted\" note")
        #expect(rows[1][13] == "true")
    }
}

private struct CSVFixtureParser {
    func parse(_ data: Data) throws -> [[String]] {
        let text = try #require(String(data: data, encoding: .utf8))
        var rows: [[String]] = [[]]
        var field = ""
        var isQuoted = false
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" {
                if isQuoted, index + 1 < scalars.count,
                   scalars[index + 1] == "\""
                {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if scalar == ",", !isQuoted {
                rows[rows.count - 1].append(field)
                field = ""
            } else if scalar == "\n", !isQuoted {
                rows[rows.count - 1].append(field)
                rows.append([])
                field = ""
            } else if scalar != "\r" {
                field.unicodeScalars.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !rows[rows.count - 1].isEmpty {
            rows[rows.count - 1].append(field)
        } else {
            rows.removeLast()
        }
        return rows
    }
}
