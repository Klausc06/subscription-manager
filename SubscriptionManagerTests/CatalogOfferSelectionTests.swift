import Foundation
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct CatalogOfferSelectionTests {
    @Test("Selection excludes offers that require review")
    func excludesReviewRequiredOffers() {
        let preset = preset(
            offers: [
                offer(id: "verified", interval: .monthly, status: .verified),
                offer(
                    id: "review",
                    interval: .yearly,
                    status: .reviewRequired
                )
            ]
        )

        #expect(
            CatalogOfferSelection.selectableOffers(in: preset).map(\.id)
                == ["verified"]
        )
    }

    @Test("Monthly is the deterministic default period")
    func monthlyIsDefault() {
        let preset = preset(
            offers: [
                offer(id: "annual", interval: .yearly),
                offer(id: "monthly", interval: .monthly)
            ]
        )

        #expect(CatalogOfferSelection.defaultOffer(in: preset)?.id == "monthly")
        #expect(CatalogOfferSelection.periods(in: preset) == ["monthly", "yearly"])
    }

    @Test("A monthly-only service has one selectable period")
    func monthlyOnlyServiceUsesItsOfferAsDefault() {
        let preset = preset(offers: [offer(id: "monthly", interval: .monthly)])

        #expect(CatalogOfferSelection.periods(in: preset) == ["monthly"])
        #expect(CatalogOfferSelection.defaultOffer(in: preset)?.id == "monthly")
    }

    @Test("Selecting a yearly period filters out monthly offers")
    func yearlyPeriodFiltersOffers() {
        let preset = preset(
            offers: [
                offer(id: "monthly", interval: .monthly),
                offer(id: "annual", interval: .yearly)
            ]
        )

        #expect(
            CatalogOfferSelection.offers(in: preset, periodRawValue: "yearly")
                .map(\.id) == ["annual"]
        )
    }

    @Test("Selectable offers use stable plan-name ordering")
    func selectableOffersHaveStableOrdering() {
        let preset = preset(
            offers: [
                offer(
                    id: "premium",
                    planName: "Premium",
                    minorUnits: 2_000,
                    interval: .monthly
                ),
                offer(
                    id: "starter",
                    planName: "Starter",
                    minorUnits: 800,
                    interval: .monthly
                ),
                offer(
                    id: "annual",
                    planName: "Annual",
                    minorUnits: 500,
                    interval: .yearly
                )
            ]
        )

        #expect(
            CatalogOfferSelection.selectableOffers(in: preset)
                .map(\.planName.en) == ["Starter", "Premium", "Annual"]
        )
    }

    @Test("Custom periods use raw values as a deterministic tie-breaker")
    func customPeriodsHaveStableOrdering() {
        let preset = preset(
            offers: [
                offer(
                    id: "seven-days",
                    interval: .custom(value: 7, unit: .day)
                ),
                offer(
                    id: "two-months",
                    interval: .custom(value: 2, unit: .month)
                )
            ]
        )

        #expect(
            CatalogOfferSelection.periods(in: preset)
                == ["custom:2:month", "custom:7:day"]
        )
    }

    @Test("Custom offer ordering uses raw values before price")
    func customOffersHaveStableOrdering() {
        let preset = preset(
            offers: [
                offer(
                    id: "seven-days",
                    minorUnits: 100,
                    interval: .custom(value: 7, unit: .day)
                ),
                offer(
                    id: "two-months",
                    minorUnits: 1_000,
                    interval: .custom(value: 2, unit: .month)
                )
            ]
        )

        #expect(
            CatalogOfferSelection.selectableOffers(in: preset).map(\.id)
                == ["two-months", "seven-days"]
        )
    }

    @Test("Offer-less legacy services have no selection")
    func offerLessLegacyServiceHasNoSelection() {
        let legacyPreset = preset()

        #expect(CatalogOfferSelection.selectableOffers(in: legacyPreset).isEmpty)
        #expect(CatalogOfferSelection.periods(in: legacyPreset).isEmpty)
        #expect(CatalogOfferSelection.defaultOffer(in: legacyPreset) == nil)
    }
}

private func preset(offers: [CatalogOffer] = []) -> CatalogPreset {
    CatalogPreset(
        id: "example",
        serviceName: CatalogLocalizedText(en: "Example", zhHans: "示例"),
        category: CatalogLocalizedText(en: "Other", zhHans: "其他"),
        suggestedInterval: .monthly,
        managementURL: nil,
        icon: .other,
        offers: offers
    )
}

private func offer(
    id: String,
    planName: String = "Plan",
    minorUnits: Int64 = 2_000,
    interval: BillingInterval,
    status: CatalogOfferReviewStatus = .verified
) -> CatalogOffer {
    CatalogOffer(
        id: id,
        planName: CatalogLocalizedText(en: planName, zhHans: planName),
        price: Money(minorUnits: minorUnits, currency: .usd),
        billingInterval: interval,
        market: "US",
        purchaseChannel: .web,
        sourceURL: URL(string: "https://example.com/pricing")!,
        verifiedOn: "2026-07-30",
        reviewStatus: status
    )
}
