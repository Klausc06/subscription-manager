import Foundation
import Testing

@testable import SubscriptionCore

@Suite("Subscription table query")
struct LibraryQueriesTests {
    private func summary(
        id: UUID,
        serviceName: String,
        plan: String = "Standard",
        category: String = "Media",
        pinnedAt: Date? = nil
    ) -> SubscriptionSummary {
        let anchor = Date(timeIntervalSince1970: 1_767_225_600)
        return SubscriptionSummary(
            subscription: Subscription(
                id: id,
                serviceIdentity: ServiceIdentity(
                    rawValue: "manual:\(id.uuidString.lowercased())"
                ),
                serviceName: serviceName,
                plan: plan,
                category: category,
                originalAmount: Money(minorUnits: 1_000, currency: .usd),
                billingSchedule: FixedBillingSchedule(
                    interval: .monthly,
                    renewalAnchor: anchor,
                    timeZoneIdentifier: "UTC"
                ),
                startDate: anchor,
                confirmedNextRenewal: anchor,
                managementURL: nil,
                notes: "",
                pinnedAt: pinnedAt
            ),
            status: .active,
            nextExpectedCharge: nil
        )
    }

    private func identifier(_ suffix: String) -> UUID {
        UUID(uuidString: "00000000-0000-4000-8000-00000000\(suffix)")!
    }

    /// Swedish collation orders "Ä" after "Z"; English orders it beside "A".
    /// The query must follow the locale it is handed rather than the process
    /// locale, so a surface carrying its own locale sorts in that locale.
    @Test("Service-name ordering follows the supplied locale")
    func serviceNameOrderingFollowsLocale() {
        let zebra = identifier("0001")
        let apple = identifier("0002")
        let summaries = [
            summary(id: zebra, serviceName: "Zebra"),
            summary(id: apple, serviceName: "Äpple"),
        ]
        let query = SubscriptionTableQuery(sort: .serviceName)

        let english = query.apply(
            to: summaries,
            locale: Locale(identifier: "en_US")
        )
        let swedish = query.apply(
            to: summaries,
            locale: Locale(identifier: "sv_SE")
        )

        #expect(english.map(\.id) == [apple, zebra])
        #expect(swedish.map(\.id) == [zebra, apple])
    }

    @Test("Search matches service name, plan, and category")
    func searchMatchesEveryDescribedField() {
        let byName = identifier("0011")
        let byPlan = identifier("0012")
        let byCategory = identifier("0013")
        let unmatched = identifier("0014")
        let summaries = [
            summary(id: byName, serviceName: "Lumina"),
            summary(id: byPlan, serviceName: "Other", plan: "Lumina Premium"),
            summary(
                id: byCategory,
                serviceName: "Other",
                plan: "Standard",
                category: "Lumina Tools"
            ),
            summary(id: unmatched, serviceName: "Unrelated"),
        ]

        let matched = Set(
            SubscriptionTableQuery(searchText: "lumina")
                .apply(to: summaries)
                .map(\.id)
        )

        #expect(matched == [byName, byPlan, byCategory])
    }

    @Test("Search ignores surrounding whitespace and diacritics")
    func searchNormalizesInput() {
        let target = identifier("0021")
        let summaries = [summary(id: target, serviceName: "Café Cloud")]

        let padded = SubscriptionTableQuery(searchText: "  cafe  ")
            .apply(to: summaries)

        #expect(padded.map(\.id) == [target])
    }

    @Test("An empty search keeps every row")
    func emptySearchKeepsEveryRow() {
        let first = identifier("0031")
        let second = identifier("0032")
        let summaries = [
            summary(id: first, serviceName: "Alpha"),
            summary(id: second, serviceName: "Beta"),
        ]

        let result = SubscriptionTableQuery(searchText: "   ")
            .apply(to: summaries)

        #expect(result.count == 2)
    }

    @Test("Pinned rows precede ordinary rows in either direction")
    func pinnedRowsAlwaysLeadRegardlessOfDirection() {
        let pinned = identifier("0041")
        let ordinary = identifier("0042")
        let summaries = [
            summary(id: ordinary, serviceName: "Alpha"),
            summary(
                id: pinned,
                serviceName: "Zulu",
                pinnedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        ]

        for ascending in [true, false] {
            let result = SubscriptionTableQuery(
                sort: .serviceName,
                ascending: ascending
            )
            .apply(to: summaries)

            #expect(result.first?.id == pinned)
        }
    }

    @Test("Descending order reverses only the ordinary rows")
    func descendingReversesOrdinaryRows() {
        let alpha = identifier("0051")
        let beta = identifier("0052")
        let summaries = [
            summary(id: alpha, serviceName: "Alpha"),
            summary(id: beta, serviceName: "Beta"),
        ]
        let query = { (ascending: Bool) in
            SubscriptionTableQuery(sort: .serviceName, ascending: ascending)
                .apply(to: summaries)
                .map(\.id)
        }

        #expect(query(true) == [alpha, beta])
        #expect(query(false) == [beta, alpha])
    }
}
