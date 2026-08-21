import Foundation
import Testing
@testable import SubscriptionCore

@Suite("Catalog offer matching")
struct CatalogOfferMatcherTests {
    @Test("An explicit alias matches with whitespace case and diacritic folding")
    func explicitAliasMatchesNormalizedText() throws {
        let preset = makePreset(
            matchAliases: ["ChatGPT Plus"],
            offers: [makeOffer()]
        )
        let snapshot = try makeSnapshot(presets: [preset])
        let subscription = makeSubscription(
            serviceName: "  ChátGPT \n PLUS  "
        )

        let result = CatalogOfferMatcher().match(
            subscription: subscription,
            in: snapshot,
            onBillingDay: referenceDate
        )

        #expect(
            result == .unique(
                CatalogOfferMatchCandidate(
                    preset: preset,
                    offer: preset.offers[0]
                )
            )
        )
    }

    @Test("A legacy identity constrains a matching name to its canonical preset")
    func legacyIdentitySelectsCanonicalPreset() throws {
        let intended = makePreset(
            id: "chatgpt",
            legacyPresetIDs: ["chatgpt-plus"],
            offers: [makeOffer()]
        )
        let competing = makePreset(
            id: "competing",
            serviceName: "ChatGPT",
            offers: [makeOffer(id: "competing-plus")]
        )
        let subscription = makeSubscription(
            serviceIdentity: ServiceIdentity(
                rawValue: "catalog:chatgpt-plus"
            ),
            serviceName: "ChatGPT"
        )

        let result = CatalogOfferMatcher().match(
            subscription: subscription,
            in: try makeSnapshot(presets: [intended, competing]),
            onBillingDay: referenceDate
        )

        #expect(
            result == .unique(
                CatalogOfferMatchCandidate(
                    preset: intended,
                    offer: intended.offers[0]
                )
            )
        )
    }

    @Test("A catalog identity cannot bypass a mismatched service name")
    func catalogIdentityRequiresMatchingName() throws {
        let preset = makePreset(
            id: "chatgpt",
            legacyPresetIDs: ["chatgpt-plus"],
            offers: [makeOffer()]
        )
        let subscription = makeSubscription(
            serviceIdentity: ServiceIdentity(
                rawValue: "catalog:chatgpt-plus"
            ),
            serviceName: "Unrelated Service"
        )

        #expect(
            CatalogOfferMatcher().match(
                subscription: subscription,
                in: try makeSnapshot(presets: [preset]),
                onBillingDay: referenceDate
            ) == .none
        )
    }

    @Test("Only verified offers participate")
    func excludesReviewRequiredOffers() throws {
        let snapshot = try makeSnapshot(
            presets: [
                makePreset(
                    offers: [
                        makeOffer(reviewStatus: .reviewRequired),
                        makeOffer(id: "verified-nonmatch", price: 999),
                    ]
                ),
            ]
        )

        #expect(
            CatalogOfferMatcher().match(
                subscription: makeSubscription(),
                in: snapshot,
                onBillingDay: referenceDate
            ) == .none
        )
    }

    @Test("Price currency and interval must all match")
    func requiresExactOfferFacts() throws {
        let snapshot = try makeSnapshot(
            presets: [makePreset(offers: [makeOffer()])]
        )
        let matcher = CatalogOfferMatcher()

        #expect(
            matcher.match(
                subscription: makeSubscription(amount: 1_999),
                in: snapshot,
                onBillingDay: referenceDate
            ) == .none
        )
        #expect(
            matcher.match(
                subscription: makeSubscription(currency: .cny),
                in: snapshot,
                onBillingDay: referenceDate
            ) == .none
        )
        #expect(
            matcher.match(
                subscription: makeSubscription(interval: .yearly),
                in: snapshot,
                onBillingDay: referenceDate
            ) == .none
        )
    }

    @Test("Catalog adjustments are derived from the unique verified plan")
    func derivesCatalogOfferAdjustmentsWithoutStoredFlags() throws {
        let preset = makePreset(offers: [makeOffer()])
        let snapshot = try makeSnapshot(presets: [preset])
        let matcher = CatalogOfferMatcher()
        let identity = ServiceIdentity(rawValue: "catalog:chatgpt")

        #expect(
            matcher.adjustment(
                for: makeSubscription(
                    serviceIdentity: identity,
                    plan: "Plus"
                ),
                in: snapshot,
                onBillingDay: referenceDate
            ) == CatalogOfferAdjustment(
                isPriceAdjusted: false,
                isScheduleAdjusted: false
            )
        )
        #expect(
            matcher.adjustment(
                for: makeSubscription(
                    serviceIdentity: identity,
                    plan: "Plus",
                    amount: 2_100
                ),
                in: snapshot,
                onBillingDay: referenceDate
            ) == CatalogOfferAdjustment(
                isPriceAdjusted: true,
                isScheduleAdjusted: false
            )
        )
        #expect(
            matcher.adjustment(
                for: makeSubscription(
                    serviceIdentity: identity,
                    plan: "Plus",
                    interval: .yearly
                ),
                in: snapshot,
                onBillingDay: referenceDate
            ) == CatalogOfferAdjustment(
                isPriceAdjusted: false,
                isScheduleAdjusted: true
            )
        )
    }

    @Test("Catalog adjustment stays unknown when the reference offer ties")
    func rejectsAmbiguousCatalogAdjustmentReference() throws {
        let preset = makePreset(
            offers: [
                makeOffer(id: "plus-monthly-web"),
                makeOffer(id: "plus-monthly-ios"),
            ]
        )

        #expect(
            CatalogOfferMatcher().adjustment(
                for: makeSubscription(
                    serviceIdentity: ServiceIdentity(
                        rawValue: "catalog:chatgpt"
                    ),
                    plan: "Plus"
                ),
                in: try makeSnapshot(presets: [preset]),
                onBillingDay: referenceDate
            ) == nil
        )
    }

    @Test("Conflicting same-plan offer facts stay unknown")
    func rejectsConflictingSamePlanOfferFacts() throws {
        let snapshot = try makeSnapshot(
            presets: [
                makePreset(
                    offers: [
                        makeOffer(
                            id: "plus-monthly",
                            price: 1_200,
                            interval: .monthly
                        ),
                        makeOffer(
                            id: "plus-yearly",
                            price: 12_000,
                            interval: .yearly
                        ),
                    ]
                ),
            ]
        )

        #expect(
            CatalogOfferMatcher().adjustment(
                for: makeSubscription(
                    serviceIdentity: ServiceIdentity(
                        rawValue: "catalog:chatgpt"
                    ),
                    plan: "Plus",
                    amount: 1_200,
                    interval: .yearly
                ),
                in: snapshot,
                onBillingDay: referenceDate
            ) == nil
        )
        #expect(
            CatalogOfferMatcher().adjustment(
                for: makeSubscription(
                    serviceIdentity: ServiceIdentity(
                        rawValue: "catalog:chatgpt"
                    ),
                    plan: "Plus",
                    amount: 12_000,
                    interval: .monthly
                ),
                in: snapshot,
                onBillingDay: referenceDate
            ) == nil
        )
    }

    @Test("A unique same-plan price derives a custom schedule adjustment")
    func derivesCustomScheduleAdjustmentAcrossSamePlanCadences() throws {
        let snapshot = try makeSnapshot(
            presets: [
                makePreset(
                    offers: [
                        makeOffer(
                            id: "plus-monthly",
                            price: 1_200,
                            interval: .monthly
                        ),
                        makeOffer(
                            id: "plus-yearly",
                            price: 12_000,
                            interval: .yearly
                        ),
                    ]
                ),
            ]
        )

        #expect(
            CatalogOfferMatcher().adjustment(
                for: makeSubscription(
                    serviceIdentity: ServiceIdentity(
                        rawValue: "catalog:chatgpt"
                    ),
                    plan: "Plus",
                    amount: 1_200,
                    interval: .custom(value: 2, unit: .month)
                ),
                in: snapshot,
                onBillingDay: referenceDate
            ) == CatalogOfferAdjustment(
                isPriceAdjusted: false,
                isScheduleAdjusted: true
            )
        )
    }

    @Test("The matcher rejects partial fuzzy and legacy-ID text")
    func rejectsUnlistedTextVariants() throws {
        let preset = makePreset(
            id: "chatgpt",
            legacyPresetIDs: ["chatgpt-plus"],
            offers: [makeOffer()]
        )
        let snapshot = try makeSnapshot(presets: [preset])
        let matcher = CatalogOfferMatcher()

        for name in ["ChatGPT P", "Chat GPT", "chatgpt-plus"] {
            #expect(
                matcher.match(
                    subscription: makeSubscription(serviceName: name),
                    in: snapshot,
                    onBillingDay: referenceDate
                ) == .none
            )
        }
    }

    @Test("Multiple exact preset and offer pairs are ambiguous")
    func reportsAmbiguousMatches() throws {
        let first = makePreset(
            id: "first",
            matchAliases: ["ChatGPT Plus"],
            offers: [makeOffer(id: "first-plus")]
        )
        let second = makePreset(
            id: "second",
            matchAliases: ["ChatGPT Plus"],
            offers: [makeOffer(id: "second-plus")]
        )

        #expect(
            CatalogOfferMatcher().match(
                subscription: makeSubscription(
                    serviceName: "ChatGPT Plus"
                ),
                in: try makeSnapshot(presets: [first, second]),
                onBillingDay: referenceDate
            ) == .ambiguous
        )
    }

    @Test("The billing-local current price change supplies the effective amount")
    func matchesEffectiveCurrentAmount() throws {
        let calendar = utcCalendar
        let past = calendar.date(
            byAdding: .day,
            value: -1,
            to: referenceDate
        )!
        let future = calendar.date(
            byAdding: .day,
            value: 1,
            to: referenceDate
        )!
        let subscription = makeSubscription(
            amount: 1_000,
            confirmedNextRenewal: future,
            priceChanges: [
                PriceChange(
                    id: UUID(
                        uuidString: "10000000-0000-0000-0000-000000000001"
                    )!,
                    effectiveDate: past,
                    amount: Money(minorUnits: 2_000, currency: .usd)
                ),
                PriceChange(
                    id: UUID(
                        uuidString: "10000000-0000-0000-0000-000000000002"
                    )!,
                    effectiveDate: future,
                    amount: Money(minorUnits: 3_000, currency: .usd)
                ),
            ]
        )

        let result = CatalogOfferMatcher().match(
            subscription: subscription,
            in: try makeSnapshot(
                presets: [makePreset(offers: [makeOffer(price: 3_000)])]
            ),
            onBillingDay: subscription.confirmedNextRenewal
        )

        guard case .unique = result else {
            Issue.record("Expected the current effective amount to match.")
            return
        }
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_769_731_200)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeSnapshot(
        presets: [CatalogPreset]
    ) throws -> CatalogSnapshot {
        try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            presets: presets
        )
    }

    private func makePreset(
        id: String = "chatgpt",
        serviceName: String = "ChatGPT",
        legacyPresetIDs: [String] = [],
        matchAliases: [String] = [],
        offers: [CatalogOffer]
    ) -> CatalogPreset {
        CatalogPreset(
            id: id,
            serviceName: CatalogLocalizedText(
                en: serviceName,
                zhHans: serviceName
            ),
            category: CatalogLocalizedText(
                en: "Productivity",
                zhHans: "效率"
            ),
            suggestedInterval: .monthly,
            managementURL: URL(string: "https://chatgpt.com/"),
            icon: .productivity,
            legacyPresetIDs: legacyPresetIDs,
            matchAliases: matchAliases,
            offers: offers
        )
    }

    private func makeOffer(
        id: String = "plus-monthly",
        price: Int64 = 2_000,
        interval: BillingInterval = .monthly,
        reviewStatus: CatalogOfferReviewStatus = .verified
    ) -> CatalogOffer {
        CatalogOffer(
            id: id,
            planName: CatalogLocalizedText(en: "Plus", zhHans: "Plus"),
            price: Money(minorUnits: price, currency: .usd),
            billingInterval: interval,
            market: "US",
            purchaseChannel: .web,
            sourceURL: URL(string: "https://example.com/pricing")!,
            verifiedOn: "2026-07-30",
            reviewStatus: reviewStatus
        )
    }

    private func makeSubscription(
        serviceIdentity: ServiceIdentity = ServiceIdentity(
            rawValue: "manual:10000000-0000-0000-0000-000000000000"
        ),
        serviceName: String = "ChatGPT",
        plan: String = "User Entered",
        amount: Int64 = 2_000,
        currency: Currency = .usd,
        interval: BillingInterval = .monthly,
        confirmedNextRenewal: Date? = nil,
        priceChanges: [PriceChange] = []
    ) -> Subscription {
        Subscription(
            id: UUID(
                uuidString: "20000000-0000-0000-0000-000000000000"
            )!,
            serviceIdentity: serviceIdentity,
            serviceName: serviceName,
            plan: plan,
            category: "Other",
            originalAmount: Money(
                minorUnits: amount,
                currency: currency
            ),
            billingCycle: interval,
            startDate: referenceDate,
            confirmedNextRenewal: confirmedNextRenewal ?? referenceDate,
            billingTimeZoneIdentifier: "UTC",
            managementURL: nil,
            notes: "",
            priceChanges: priceChanges
        )
    }
}
