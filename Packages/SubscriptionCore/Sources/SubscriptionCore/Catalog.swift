import Foundation

public enum CatalogValidationField: String, Equatable, Sendable {
    case schemaVersion
    case catalogVersion
    case id
    case serviceName
    case category
    case suggestedInterval
    case managementURL
    case assetProvenance
    case matchAliases
    case offers
}

public struct CatalogLoadError: Error, Equatable, Sendable,
    CustomStringConvertible
{
    public let presetID: String?
    public let field: CatalogValidationField
    public let message: String

    public init(
        presetID: String?,
        field: CatalogValidationField,
        message: String
    ) {
        self.presetID = presetID
        self.field = field
        self.message = message
    }

    public var description: String {
        "catalog validation failed: preset=\(presetID ?? "snapshot") "
            + "field=\(field.rawValue) reason=\(message)"
    }
}

public struct CatalogLocalizedText: Codable, Equatable, Hashable, Sendable {
    public let en: String
    public let zhHans: String

    public init(en: String, zhHans: String) {
        self.en = en
        self.zhHans = zhHans
    }

    public func value(for locale: Locale) -> String {
        locale.language.languageCode?.identifier == "zh" ? zhHans : en
    }

    fileprivate var isValid: Bool {
        !en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !zhHans.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum CatalogIcon: String, Codable, CaseIterable, Sendable {
    case cloud
    case game
    case membership
    case music
    case news
    case other
    case productivity
    case reading
    case video
}

public enum CatalogAssetKind: String, Codable, Sendable {
    case originalSymbol
}

public struct CatalogAssetProvenance: Codable, Equatable, Sendable {
    public let kind: CatalogAssetKind
    public let license: String
    public let source: String

    public init(kind: CatalogAssetKind, license: String, source: String) {
        self.kind = kind
        self.license = license
        self.source = source
    }

    static func originalSymbol(for presetID: String) -> Self {
        Self(
            kind: .originalSymbol,
            license: "CC0-1.0",
            source: presetID
        )
    }
}

public struct CatalogCategory: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: CatalogLocalizedText

    public init(id: String, title: CatalogLocalizedText) {
        self.id = id
        self.title = title
    }
}

public enum CatalogState: Equatable, Sendable {
    case notLoaded
    case loaded(categories: [CatalogCategory], presets: [CatalogPreset])
    case failed
}

public enum CatalogSource: String, Equatable, Sendable {
    case bundled
    case cached
}

public enum CatalogRefreshStatus: Equatable, Sendable {
    case idle
    case updated
    case alreadyCurrent
    case failed
}

public struct CatalogDiagnostics: Equatable, Sendable {
    public let source: CatalogSource
    public let version: Int
    public let refreshStatus: CatalogRefreshStatus

    public init(
        source: CatalogSource,
        version: Int,
        refreshStatus: CatalogRefreshStatus
    ) {
        self.source = source
        self.version = version
        self.refreshStatus = refreshStatus
    }
}

public enum CatalogPurchaseChannel: String, Codable, Equatable, Sendable {
    case web
    case ios = "iOS"
}

public enum CatalogOfferReviewStatus: String, Codable, Equatable, Sendable {
    case verified
    case reviewRequired
}

public struct CatalogOffer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let planName: CatalogLocalizedText
    public let price: Money
    public let billingInterval: BillingInterval
    public let market: String
    public let purchaseChannel: CatalogPurchaseChannel
    public let sourceURL: URL
    public let verifiedOn: String
    public let reviewStatus: CatalogOfferReviewStatus

    public init(
        id: String,
        planName: CatalogLocalizedText,
        price: Money,
        billingInterval: BillingInterval,
        market: String,
        purchaseChannel: CatalogPurchaseChannel,
        sourceURL: URL,
        verifiedOn: String,
        reviewStatus: CatalogOfferReviewStatus
    ) {
        self.id = id
        self.planName = planName
        self.price = price
        self.billingInterval = billingInterval
        self.market = market
        self.purchaseChannel = purchaseChannel
        self.sourceURL = sourceURL
        self.verifiedOn = verifiedOn
        self.reviewStatus = reviewStatus
    }
}

public struct CatalogPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let serviceName: CatalogLocalizedText
    public let category: CatalogLocalizedText
    public let categoryID: String
    public let suggestedInterval: BillingInterval
    public let managementURL: URL?
    public let icon: CatalogIcon
    public let assetProvenance: CatalogAssetProvenance
    public let legacyPresetIDs: [String]
    public let matchAliases: [String]
    public let offers: [CatalogOffer]

    public init(
        id: String,
        serviceName: CatalogLocalizedText,
        category: CatalogLocalizedText,
        suggestedInterval: BillingInterval,
        managementURL: URL?,
        icon: CatalogIcon,
        categoryID: String? = nil,
        assetProvenance: CatalogAssetProvenance? = nil,
        legacyPresetIDs: [String] = [],
        matchAliases: [String] = [],
        offers: [CatalogOffer] = []
    ) {
        self.id = id
        self.serviceName = serviceName
        self.category = category
        self.categoryID = categoryID?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? Self.normalizedCategoryID(category.en)
        self.suggestedInterval = suggestedInterval
        self.managementURL = managementURL
        self.icon = icon
        self.assetProvenance = assetProvenance
            ?? .originalSymbol(for: id)
        self.legacyPresetIDs = legacyPresetIDs
        self.matchAliases = matchAliases
        self.offers = offers
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case serviceName
        case category
        case categoryID
        case suggestedInterval
        case managementURL
        case icon
        case assetProvenance
        case legacyPresetIDs
        case matchAliases
        case offers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            serviceName: try container.decode(
                CatalogLocalizedText.self,
                forKey: .serviceName
            ),
            category: try container.decode(
                CatalogLocalizedText.self,
                forKey: .category
            ),
            suggestedInterval: try container.decode(
                BillingInterval.self,
                forKey: .suggestedInterval
            ),
            managementURL: try container.decodeIfPresent(
                URL.self,
                forKey: .managementURL
            ),
            icon: try container.decode(CatalogIcon.self, forKey: .icon),
            categoryID: try container.decodeIfPresent(
                String.self,
                forKey: .categoryID
            ),
            assetProvenance: try container.decodeIfPresent(
                CatalogAssetProvenance.self,
                forKey: .assetProvenance
            ),
            legacyPresetIDs: try container.decodeIfPresent(
                [String].self,
                forKey: .legacyPresetIDs
            ) ?? [],
            matchAliases: try container.decodeIfPresent(
                [String].self,
                forKey: .matchAliases
            ) ?? [],
            offers: try container.decodeIfPresent(
                [CatalogOffer].self,
                forKey: .offers
            ) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(serviceName, forKey: .serviceName)
        try container.encode(category, forKey: .category)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(suggestedInterval, forKey: .suggestedInterval)
        try container.encodeIfPresent(managementURL, forKey: .managementURL)
        try container.encode(icon, forKey: .icon)
        try container.encode(assetProvenance, forKey: .assetProvenance)
        if !legacyPresetIDs.isEmpty {
            try container.encode(legacyPresetIDs, forKey: .legacyPresetIDs)
        }
        if !matchAliases.isEmpty {
            try container.encode(matchAliases, forKey: .matchAliases)
        }
        if !offers.isEmpty {
            try container.encode(offers, forKey: .offers)
        }
    }

    private static func normalizedCategoryID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en")
        )
    }
}

public struct CatalogSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let catalogVersion: Int
    public let presets: [CatalogPreset]

    public init(
        schemaVersion: Int,
        catalogVersion: Int = 1,
        presets: [CatalogPreset]
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CatalogLoadError(
                presetID: nil,
                field: .schemaVersion,
                message: "unsupported schema version"
            )
        }
        guard catalogVersion > 0 else {
            throw CatalogLoadError(
                presetID: nil,
                field: .catalogVersion,
                message: "catalog version must be positive"
            )
        }
        var identifiers = Set<String>()
        for preset in presets {
            let identifier = preset.id.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard preset.id == identifier else {
                throw CatalogLoadError(
                    presetID: identifier.isEmpty ? nil : identifier,
                    field: .id,
                    message: "preset ID must not have leading or trailing whitespace"
                )
            }
            guard !identifier.isEmpty, identifiers.insert(identifier).inserted else {
                throw CatalogLoadError(
                    presetID: identifier.isEmpty ? nil : identifier,
                    field: .id,
                    message: "identifier is empty or duplicated"
                )
            }
            guard preset.serviceName.isValid else {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .serviceName,
                    message: "English and Simplified Chinese text are required"
                )
            }
            guard preset.category.isValid else {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .category,
                    message: "English and Simplified Chinese text are required"
                )
            }
            guard !preset.categoryID.isEmpty else {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .category,
                    message: "stable category identifier is required"
                )
            }
            guard preset.suggestedInterval.isValid else {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .suggestedInterval,
                    message: "billing interval is unsupported"
                )
            }
            if let url = preset.managementURL {
                guard (url.scheme?.lowercased() == "http"
                    || url.scheme?.lowercased() == "https"),
                    let host = url.host,
                    !host.isEmpty
                else {
                    throw CatalogLoadError(
                        presetID: identifier,
                        field: .managementURL,
                        message: "URL must use HTTP or HTTPS and have a host"
                    )
                }
            }
            guard preset.assetProvenance.kind == .originalSymbol,
                  preset.assetProvenance.license == "CC0-1.0",
                  preset.assetProvenance.source == identifier
            else {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .assetProvenance,
                    message: "asset must be an original CC0 symbol for this preset"
                )
            }
            for legacyPresetID in preset.legacyPresetIDs {
                let legacyIdentifier = legacyPresetID.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !legacyIdentifier.isEmpty,
                      identifiers.insert(legacyIdentifier).inserted
                else {
                    throw CatalogLoadError(
                        presetID: identifier,
                        field: .id,
                        message: "legacy identifier is empty or duplicated"
                    )
                }
            }
            var normalizedAliases = Set<String>()
            for alias in preset.matchAliases {
                let normalizedAlias = CatalogOfferMatcher.normalizedText(alias)
                guard !normalizedAlias.isEmpty,
                      normalizedAliases.insert(normalizedAlias).inserted
                else {
                    throw CatalogLoadError(
                        presetID: identifier,
                        field: .matchAliases,
                        message: "match alias is empty or duplicated"
                    )
                }
            }
            guard preset.offers.contains(where: {
                $0.reviewStatus == .verified
            }) else {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .offers,
                    message: "preset must include at least one verified offer"
                )
            }
            var offerIdentifiers = Set<String>()
            for offer in preset.offers {
                let offerID = offer.id.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !offerID.isEmpty,
                      offerIdentifiers.insert(offerID).inserted,
                      offer.planName.isValid,
                      offer.price.minorUnits > 0,
                      offer.billingInterval.isValid,
                      !offer.market.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ).isEmpty,
                      offer.sourceURL.scheme?.lowercased() == "https",
                      isValidCatalogVerificationDate(offer.verifiedOn)
                else {
                    throw CatalogLoadError(
                        presetID: identifier,
                        field: .offers,
                        message: "offer is invalid or duplicated"
                    )
                }
            }
        }
        self.schemaVersion = schemaVersion
        self.catalogVersion = catalogVersion
        self.presets = presets
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            catalogVersion: container.decode(Int.self, forKey: .catalogVersion),
            presets: container.decode([CatalogPreset].self, forKey: .presets)
        )
    }

    public func search(query: String, locale: Locale) -> [CatalogPreset] {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let foldedQuery = normalizedQuery.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        )
        func matches(_ value: String) -> Bool {
            value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            ).contains(foldedQuery)
        }
        return presets.filter { preset in
            guard !normalizedQuery.isEmpty else { return true }
            return matches(preset.serviceName.value(for: locale))
                || matches(preset.category.value(for: locale))
                || preset.matchAliases.contains { matches($0) }
        }
        .sorted { left, right in
            let comparison = left.serviceName.value(for: locale).localizedCompare(
                right.serviceName.value(for: locale)
            )
            return comparison == .orderedSame
                ? left.id < right.id
                : comparison == .orderedAscending
        }
    }

    public func categories(locale: Locale) -> [CatalogCategory] {
        let categories = Dictionary(
            presets.map {
                (
                    $0.categoryID,
                    CatalogCategory(
                        id: $0.categoryID,
                        title: $0.category
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        return categories.values.sorted {
            $0.title.value(for: locale).localizedCompare(
                $1.title.value(for: locale)
            ) == .orderedAscending
        }
    }

    public func canonicalPresetID(for identifier: String) -> String? {
        let normalized = identifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return presets.first {
            $0.id == normalized || $0.legacyPresetIDs.contains(normalized)
        }?.id
    }
}

private func isValidCatalogVerificationDate(_ value: String) -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value) else {
        return false
    }
    return formatter.string(from: date) == value
}

@MainActor
public protocol CatalogRepository {
    func loadSnapshot() throws -> CatalogSnapshot
    var catalogSource: CatalogSource { get }
}

public extension CatalogRepository {
    var catalogSource: CatalogSource { .bundled }
}

@MainActor
public protocol CatalogUpdateSource {
    func fetchCatalogData() async throws -> Data
}

@MainActor
public protocol CatalogCache {
    func storeCatalogData(_ data: Data) throws
}
