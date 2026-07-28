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

public struct PortableCSVEncoder: Sendable {
    public init() {}

    public func encode(
        preferences: UserPreferences,
        subscriptions: [Subscription]
    ) -> Data {
        let header = [
            "subscription_id", "service_name", "plan", "category",
            "service_identity", "billing_interval", "original_minor_units",
            "original_currency", "start_date", "confirmed_next_renewal",
            "billing_time_zone", "management_url", "notes", "is_archived",
            "lifecycle", "confirmed_charges_json", "price_changes_json",
            "preferences_json"
        ]
        let rows = subscriptions.sorted { $0.id.uuidString < $1.id.uuidString }
            .map { subscription in
                [
                    subscription.id.uuidString,
                    subscription.serviceName,
                    subscription.plan,
                    subscription.category,
                    subscription.serviceIdentity.rawValue,
                    jsonString(subscription.billingSchedule.interval),
                    String(subscription.originalAmount.minorUnits),
                    subscription.originalAmount.currency.rawValue,
                    dateString(subscription.startDate),
                    dateString(subscription.confirmedNextRenewal),
                    subscription.billingSchedule.timeZoneIdentifier,
                    subscription.managementURL?.absoluteString ?? "",
                    subscription.notes,
                    String(subscription.isArchived),
                    jsonString(subscription.lifecycle),
                    jsonString(subscription.confirmedCharges),
                    jsonString(subscription.priceChanges),
                    jsonString(preferences)
                ]
            }
        let csv = ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
        return Data(csv.utf8)
    }

    private func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(value)) ?? Data(), encoding: .utf8)
            ?? ""
    }

    private func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
