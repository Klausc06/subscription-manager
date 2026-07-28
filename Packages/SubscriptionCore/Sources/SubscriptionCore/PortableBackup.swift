import Foundation

public struct PortableBackup: Codable, Equatable, Sendable {
    public static let schemaName = "subscription-manager-backup"
    public static let currentSchemaVersion = 1

    public let schema: String
    public let schemaVersion: Int
    public let preferences: UserPreferences
    public let subscriptions: [Subscription]

    public init(
        preferences: UserPreferences,
        subscriptions: [Subscription]
    ) {
        schema = Self.schemaName
        schemaVersion = Self.currentSchemaVersion
        self.preferences = preferences
        self.subscriptions = subscriptions.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }
}

public struct PortableBackupEncoder: Sendable {
    public init() {}

    public func encode(_ backup: PortableBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public func decode(_ data: Data) throws -> PortableBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortableBackup.self, from: data)
    }
}
