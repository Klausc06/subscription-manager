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

    public func match(
        subscription: Subscription,
        in snapshot: CatalogSnapshot,
        asOf reconciliationDate: Date
    ) -> CatalogOfferMatch {
        let serviceName = Self.normalizedText(subscription.serviceName)
        guard !serviceName.isEmpty else { return .none }
        let effectiveAmount = effectiveAmount(
            for: subscription,
            asOf: reconciliationDate
        )
        let identifiedPresetID = canonicalCatalogPresetID(
            for: subscription.serviceIdentity,
            in: snapshot
        )
        let candidates = snapshot.presets.flatMap { preset in
            let names = [
                preset.serviceName.en,
                preset.serviceName.zhHans,
            ] + preset.matchAliases
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

    private func effectiveAmount(
        for subscription: Subscription,
        asOf reconciliationDate: Date
    ) -> Money {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        ) ?? TimeZone(secondsFromGMT: 0)!
        let reconciliationDay = calendar.startOfDay(for: reconciliationDate)
        return subscription.priceChanges
            .filter {
                calendar.startOfDay(for: $0.effectiveDate)
                    <= reconciliationDay
            }
            .max { left, right in
                if left.effectiveDate != right.effectiveDate {
                    return left.effectiveDate < right.effectiveDate
                }
                return left.id.uuidString < right.id.uuidString
            }?
            .amount ?? subscription.originalAmount
    }
}
