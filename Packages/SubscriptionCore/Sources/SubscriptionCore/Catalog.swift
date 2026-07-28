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

public struct CatalogPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let serviceName: CatalogLocalizedText
    public let category: CatalogLocalizedText
    public let suggestedInterval: BillingInterval
    public let managementURL: URL?
    public let icon: CatalogIcon
    public let assetProvenance: CatalogAssetProvenance

    public init(
        id: String,
        serviceName: CatalogLocalizedText,
        category: CatalogLocalizedText,
        suggestedInterval: BillingInterval,
        managementURL: URL?,
        icon: CatalogIcon,
        assetProvenance: CatalogAssetProvenance? = nil
    ) {
        self.id = id
        self.serviceName = serviceName
        self.category = category
        self.suggestedInterval = suggestedInterval
        self.managementURL = managementURL
        self.icon = icon
        self.assetProvenance = assetProvenance
            ?? .originalSymbol(for: id)
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
                    message: "English and Simplified-Chinese text are required"
                )
            }
            guard preset.category.isValid else {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .category,
                    message: "English and Simplified-Chinese text are required"
                )
            }
            guard preset.suggestedInterval.isValid else {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .suggestedInterval,
                    message: "billing interval is unsupported"
                )
            }
            if let url = preset.managementURL,
               url.scheme?.lowercased() != "http"
                && url.scheme?.lowercased() != "https"
            {
                throw CatalogLoadError(
                    presetID: identifier,
                    field: .managementURL,
                    message: "URL must use HTTP or HTTPS"
                )
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
        return presets.filter { preset in
            guard !normalizedQuery.isEmpty else { return true }
            return preset.serviceName.value(for: locale).localizedCaseInsensitiveContains(
                normalizedQuery
            ) || preset.category.value(for: locale).localizedCaseInsensitiveContains(
                normalizedQuery
            )
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
                    $0.category.en.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: "en")
                    ),
                    CatalogCategory(
                        id: $0.category.en.folding(
                            options: [.caseInsensitive, .diacriticInsensitive],
                            locale: Locale(identifier: "en")
                        ),
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
