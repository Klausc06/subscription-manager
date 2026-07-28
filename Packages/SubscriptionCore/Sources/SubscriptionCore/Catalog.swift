import Foundation

public enum CatalogLoadError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case duplicatePresetIdentifier
    case emptyLocalizedText
    case invalidManagementURL
    case invalidBillingInterval
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

public struct CatalogPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let serviceName: CatalogLocalizedText
    public let category: CatalogLocalizedText
    public let suggestedInterval: BillingInterval
    public let managementURL: URL?
    public let icon: CatalogIcon

    public init(
        id: String,
        serviceName: CatalogLocalizedText,
        category: CatalogLocalizedText,
        suggestedInterval: BillingInterval,
        managementURL: URL?,
        icon: CatalogIcon
    ) {
        self.id = id
        self.serviceName = serviceName
        self.category = category
        self.suggestedInterval = suggestedInterval
        self.managementURL = managementURL
        self.icon = icon
    }
}

public struct CatalogSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let presets: [CatalogPreset]

    public init(schemaVersion: Int, presets: [CatalogPreset]) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CatalogLoadError.unsupportedSchemaVersion
        }
        var identifiers = Set<String>()
        for preset in presets {
            let identifier = preset.id.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !identifier.isEmpty, identifiers.insert(identifier).inserted else {
                throw CatalogLoadError.duplicatePresetIdentifier
            }
            guard preset.serviceName.isValid, preset.category.isValid else {
                throw CatalogLoadError.emptyLocalizedText
            }
            guard preset.suggestedInterval.isValid else {
                throw CatalogLoadError.invalidBillingInterval
            }
            if let url = preset.managementURL,
               url.scheme?.lowercased() != "http"
                && url.scheme?.lowercased() != "https"
            {
                throw CatalogLoadError.invalidManagementURL
            }
        }
        self.schemaVersion = schemaVersion
        self.presets = presets
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
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
}

@MainActor
public protocol CatalogRepository {
    func loadSnapshot() throws -> CatalogSnapshot
}
