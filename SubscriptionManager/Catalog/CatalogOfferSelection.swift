import Foundation
import SubscriptionCore

enum CatalogOfferSelection {
    static func selectableOffers(
        in preset: CatalogPreset
    ) -> [CatalogOffer] {
        preset.offers
            .filter { $0.reviewStatus == .verified }
            .sorted(by: offerOrder)
    }

    static func periods(in preset: CatalogPreset) -> [String] {
        let values = Set(
            selectableOffers(in: preset)
                .map(\.billingInterval.rawValue)
        )
        return values.sorted {
            periodRank($0) < periodRank($1)
        }
    }

    static func defaultOffer(in preset: CatalogPreset) -> CatalogOffer? {
        let offers = selectableOffers(in: preset)
        return offers.first(where: { $0.billingInterval == .monthly })
            ?? offers.first
    }

    static func offers(
        in preset: CatalogPreset,
        periodRawValue: String
    ) -> [CatalogOffer] {
        selectableOffers(in: preset).filter {
            $0.billingInterval.rawValue == periodRawValue
        }
    }

    private static func offerOrder(
        _ lhs: CatalogOffer,
        _ rhs: CatalogOffer
    ) -> Bool {
        let leftRank = periodRank(lhs.billingInterval.rawValue)
        let rightRank = periodRank(rhs.billingInterval.rawValue)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        if lhs.price.minorUnits != rhs.price.minorUnits {
            return lhs.price.minorUnits < rhs.price.minorUnits
        }
        return lhs.id < rhs.id
    }

    private static func periodRank(_ rawValue: String) -> Int {
        switch rawValue {
        case BillingInterval.monthly.rawValue: 0
        case BillingInterval.yearly.rawValue: 1
        case BillingInterval.quarterly.rawValue: 2
        case BillingInterval.halfYearly.rawValue: 3
        case BillingInterval.weekly.rawValue: 4
        default: 5
        }
    }
}
