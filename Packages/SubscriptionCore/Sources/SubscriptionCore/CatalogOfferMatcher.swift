import Foundation

public struct CatalogOfferMatchCandidate: Equatable, Sendable {
    public let preset: CatalogPreset
    public let offer: CatalogOffer

    public init(preset: CatalogPreset, offer: CatalogOffer) {
        self.preset = preset
        self.offer = offer
    }
}

public enum CatalogOfferMatch: Equatable, Sendable {
    case none
    case unique(CatalogOfferMatchCandidate)
    case ambiguous
}

public struct CatalogOfferAdjustment: Equatable, Sendable {
    public let isPriceAdjusted: Bool
    public let isScheduleAdjusted: Bool

    public init(
        isPriceAdjusted: Bool,
        isScheduleAdjusted: Bool
    ) {
        self.isPriceAdjusted = isPriceAdjusted
        self.isScheduleAdjusted = isScheduleAdjusted
    }
}

public struct CatalogAssociationReconciliationSummary:
    Equatable,
    Sendable
{
    public let normalizedIDs: [UUID]
    public let unchangedIDs: [UUID]
    public let ambiguousIDs: [UUID]
    public let failedIDs: [UUID]
    public let commandError: CatalogAssociationReconciliationError?

    public init(
        normalizedIDs: [UUID] = [],
        unchangedIDs: [UUID] = [],
        ambiguousIDs: [UUID] = [],
        failedIDs: [UUID] = [],
        commandError: CatalogAssociationReconciliationError? = nil
    ) {
        self.normalizedIDs = normalizedIDs.sorted {
            $0.uuidString < $1.uuidString
        }
        self.unchangedIDs = unchangedIDs.sorted {
            $0.uuidString < $1.uuidString
        }
        self.ambiguousIDs = ambiguousIDs.sorted {
            $0.uuidString < $1.uuidString
        }
        self.failedIDs = failedIDs.sorted {
            $0.uuidString < $1.uuidString
        }
        self.commandError = commandError
    }
}

public enum CatalogAssociationReconciliationError:
    Equatable,
    Sendable
{
    case catalogUnavailable
    case persistenceFailed
}

public struct CatalogOfferMatcher: Sendable {
    public init() {}

    /// Returns whether the subscription service name exactly matches one of
    /// the formal localized names or aliases for its existing catalog
    /// identity. Offer price and interval are intentionally not considered;
    /// callers use this to distinguish a name rename from an offer override.
    /// Returns `nil` when the catalog cannot resolve the existing identity.
    public func matchesCatalogServiceName(
        subscription: Subscription,
        in snapshot: CatalogSnapshot
    ) -> Bool? {
        let identifiedPresetID = canonicalCatalogPresetID(
            for: subscription.serviceIdentity,
            in: snapshot
        )
        guard let identifiedPresetID,
              let preset = snapshot.presets.first(where: {
                  $0.id == identifiedPresetID
              })
        else {
            return nil
        }
        let serviceName = Self.normalizedText(subscription.serviceName)
        guard !serviceName.isEmpty else { return false }
        return formalNamesAndAliases(for: preset).contains {
            Self.normalizedText($0) == serviceName
        }
    }

    /// Derives whether a catalog subscription differs from its uniquely
    /// identifiable verified offer. The result is computed from persisted
    /// subscription facts on every load; no override flags or offer entity are
    /// stored. A tied reference remains unknown rather than guessing.
    public func adjustment(
        for subscription: Subscription,
        in snapshot: CatalogSnapshot,
        onBillingDay: Date
    ) -> CatalogOfferAdjustment? {
        guard matchesCatalogServiceName(
            subscription: subscription,
            in: snapshot
        ) == true,
        let presetID = canonicalCatalogPresetID(
            for: subscription.serviceIdentity,
            in: snapshot
        ),
        let preset = snapshot.presets.first(where: { $0.id == presetID })
        else {
            return nil
        }

        let plan = Self.normalizedText(subscription.plan)
        guard !plan.isEmpty else { return nil }
        let candidates = preset.offers.filter { offer in
            offer.reviewStatus == .verified
                && [offer.planName.en, offer.planName.zhHans].contains {
                    Self.normalizedText($0) == plan
                }
        }
        guard !candidates.isEmpty else { return nil }

        let amount = subscription.amount(onBillingDay: onBillingDay)
        func onlyCandidate(
            matching predicate: (CatalogOffer) -> Bool
        ) -> CatalogOffer? {
            let matches = candidates.filter(predicate)
            return matches.count == 1 ? matches[0] : nil
        }

        let exactReference = onlyCandidate {
            $0.price == amount
                && $0.billingInterval == subscription.billingCycle
        }
        let priceReference = onlyCandidate {
            $0.price == amount
        }
        let scheduleReference = onlyCandidate {
            $0.billingInterval == subscription.billingCycle
        }

        // A recorded price change proves `originalAmount` predates the
        // effective override, so it can safely recover the official baseline.
        // Creation-time price and cadence overrides have no such provenance;
        // when their current facts point at different same-name offers, fail
        // closed instead of reversing which fact was adjusted.
        let historyReference = subscription.priceChanges.isEmpty
            ? nil
            : onlyCandidate { $0.price == subscription.originalAmount }
        let reference: CatalogOffer?
        if let historyReference {
            reference = historyReference
        } else if let exactReference {
            reference = exactReference
        } else if let priceReference, let scheduleReference {
            reference = priceReference.id == scheduleReference.id
                ? priceReference
                : nil
        } else {
            reference = priceReference
                ?? scheduleReference
                ?? (candidates.count == 1 ? candidates[0] : nil)
        }
        guard let reference else {
            return nil
        }

        return CatalogOfferAdjustment(
            isPriceAdjusted: amount != reference.price,
            isScheduleAdjusted:
                subscription.billingCycle != reference.billingInterval
        )
    }

    public func match(
        subscription: Subscription,
        in snapshot: CatalogSnapshot,
        onBillingDay: Date
    ) -> CatalogOfferMatch {
        let serviceName = Self.normalizedText(subscription.serviceName)
        guard !serviceName.isEmpty else { return .none }
        let effectiveAmount = subscription.amount(onBillingDay: onBillingDay)
        let identifiedPresetID = canonicalCatalogPresetID(
            for: subscription.serviceIdentity,
            in: snapshot
        )
        let candidates = snapshot.presets.flatMap { preset in
            let names = formalNamesAndAliases(for: preset)
            let matchesIdentity = identifiedPresetID == preset.id
            let matchesText = names.contains {
                Self.normalizedText($0) == serviceName
            }
            guard matchesText,
                  identifiedPresetID == nil || matchesIdentity
            else {
                return [CatalogOfferMatchCandidate]()
            }
            return preset.offers.compactMap { offer in
                guard offer.reviewStatus == .verified,
                      offer.price == effectiveAmount,
                      offer.billingInterval == subscription.billingCycle
                else {
                    return nil
                }
                return CatalogOfferMatchCandidate(
                    preset: preset,
                    offer: offer
                )
            }
        }

        switch candidates.count {
        case 0:
            return .none
        case 1:
            return .unique(candidates[0])
        default:
            return .ambiguous
        }
    }

    public static func normalizedText(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private func canonicalCatalogPresetID(
        for identity: ServiceIdentity,
        in snapshot: CatalogSnapshot
    ) -> String? {
        let prefix = "catalog:"
        guard identity.rawValue.hasPrefix(prefix) else {
            return nil
        }
        let storedPresetID = String(identity.rawValue.dropFirst(prefix.count))
        return snapshot.canonicalPresetID(for: storedPresetID)
    }

    private func formalNamesAndAliases(
        for preset: CatalogPreset
    ) -> [String] {
        [
            preset.serviceName.en,
            preset.serviceName.zhHans,
        ] + preset.matchAliases
    }

}
