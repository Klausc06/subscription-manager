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
        encoder.dateEncodingStrategy = PortableBackupDateCoding.encodingStrategy
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public func decode(_ data: Data) throws -> PortableBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = PortableBackupDateCoding.decodingStrategy
        return try decoder.decode(PortableBackup.self, from: data)
    }
}

private enum PortableBackupDateCoding {
    static let encodingStrategy = JSONEncoder.DateEncodingStrategy.custom {
        date,
        encoder in
        var container = encoder.singleValueContainer()
        try container.encode(date.timeIntervalSince1970)
    }

    static let decodingStrategy = JSONDecoder.DateDecodingStrategy.custom {
        decoder in
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: seconds)
        }

        let value = try container.decode(String.self)
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a Unix timestamp or ISO 8601 date."
            )
        }
        return date
    }
}

public enum PortableBackupValidationError: Error, Equatable, Sendable {
    case malformed
    case unsupportedSchema
    case unsupportedVersion
    case duplicateSubscriptionID
    case invalidSubscription
}

public struct PortableBackupValidator: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> PortableBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = PortableBackupDateCoding.decodingStrategy
        let backup: PortableBackup
        do {
            backup = try decoder.decode(PortableBackup.self, from: data)
        } catch {
            throw PortableBackupValidationError.malformed
        }
        guard backup.schema == PortableBackup.schemaName else {
            throw PortableBackupValidationError.unsupportedSchema
        }
        guard backup.schemaVersion == PortableBackup.currentSchemaVersion else {
            throw PortableBackupValidationError.unsupportedVersion
        }
        guard Set(backup.subscriptions.map(\.id)).count
            == backup.subscriptions.count
        else {
            throw PortableBackupValidationError.duplicateSubscriptionID
        }
        guard backup.subscriptions.allSatisfy(isValid) else {
            throw PortableBackupValidationError.invalidSubscription
        }
        return backup
    }

    private func isValid(_ subscription: Subscription) -> Bool {
        let whitespace = CharacterSet.whitespacesAndNewlines
        guard !subscription.serviceIdentity.rawValue
            .trimmingCharacters(in: whitespace).isEmpty,
              !subscription.serviceName.trimmingCharacters(in: whitespace).isEmpty,
              !subscription.plan.trimmingCharacters(in: whitespace).isEmpty,
              !subscription.category.trimmingCharacters(in: whitespace).isEmpty,
              subscription.originalAmount.minorUnits > 0,
              subscription.billingSchedule.interval.isValid,
              TimeZone(identifier: subscription.billingSchedule.timeZoneIdentifier)
                != nil,
              subscription.billingSchedule.renewalAnchor >= subscription.startDate,
              subscription.confirmedNextRenewal >= subscription.startDate
        else {
            return false
        }
        return true
    }
}

public struct PortableBackupMergeConflict: Equatable, Sendable, Identifiable {
    public let local: Subscription
    public let backup: Subscription

    public var id: UUID { local.id }

    public init(local: Subscription, backup: Subscription) {
        self.local = local
        self.backup = backup
    }
}

public struct PortableBackupMergePreview: Equatable, Sendable {
    public let additions: [Subscription]
    public let unchangedSubscriptionIDs: [UUID]
    public let conflicts: [PortableBackupMergeConflict]
    public let retainedLocalSubscriptionIDs: [UUID]
    public let preferences: PortableBackupPreferencesMerge

    public init(
        additions: [Subscription],
        unchangedSubscriptionIDs: [UUID],
        conflicts: [PortableBackupMergeConflict],
        retainedLocalSubscriptionIDs: [UUID],
        preferences: PortableBackupPreferencesMerge
    ) {
        self.additions = additions
        self.unchangedSubscriptionIDs = unchangedSubscriptionIDs
        self.conflicts = conflicts
        self.retainedLocalSubscriptionIDs = retainedLocalSubscriptionIDs
        self.preferences = preferences
    }
}

public enum PortableBackupPreferencesMerge: Equatable, Sendable {
    case unchanged
    case conflict(local: UserPreferences, backup: UserPreferences)
}

public enum PortableBackupConflictResolution: Equatable, Sendable {
    case keepLocal
    case useBackup
}

public struct PortableBackupMerge: Equatable, Sendable {
    public let additions: [Subscription]
    public let replacements: [Subscription]
    public let preferences: UserPreferences?

    public init(
        additions: [Subscription],
        replacements: [Subscription],
        preferences: UserPreferences?
    ) {
        self.additions = additions.sorted { $0.id.uuidString < $1.id.uuidString }
        self.replacements = replacements.sorted { $0.id.uuidString < $1.id.uuidString }
        self.preferences = preferences
    }
}

public enum PortableBackupImportError: Error, Equatable, Sendable {
    case unavailable
    case incompleteConflictResolution
    case incompletePreferencesResolution
}

@MainActor
public protocol PortableBackupImportRepository {
    func apply(_ merge: PortableBackupMerge) throws
}

public struct PortableBackupMergePlanner: Sendable {
    public init() {}

    public func makePreview(
        backup: PortableBackup,
        localSubscriptions: [Subscription],
        localPreferences: UserPreferences
    ) throws -> PortableBackupMergePreview {
        let backupIDs = Set(backup.subscriptions.map(\.id))
        let localByID = Dictionary(
            uniqueKeysWithValues: localSubscriptions.map { ($0.id, $0) }
        )
        var additions: [Subscription] = []
        var unchangedSubscriptionIDs: [UUID] = []
        var conflicts: [PortableBackupMergeConflict] = []

        for subscription in backup.subscriptions {
            guard let local = localByID[subscription.id] else {
                additions.append(subscription)
                continue
            }
            if local == subscription {
                unchangedSubscriptionIDs.append(subscription.id)
            } else {
                conflicts.append(
                    PortableBackupMergeConflict(local: local, backup: subscription)
                )
            }
        }

        let retainedLocalSubscriptionIDs = localSubscriptions
            .filter { !backupIDs.contains($0.id) }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        let preferences: PortableBackupPreferencesMerge = backup.preferences
            == localPreferences
            ? .unchanged
            : .conflict(local: localPreferences, backup: backup.preferences)
        return PortableBackupMergePreview(
            additions: additions,
            unchangedSubscriptionIDs: unchangedSubscriptionIDs,
            conflicts: conflicts,
            retainedLocalSubscriptionIDs: retainedLocalSubscriptionIDs,
            preferences: preferences
        )
    }

    public func makeMerge(
        preview: PortableBackupMergePreview,
        selectedAdditionIDs: Set<UUID>,
        conflictResolutions: [UUID: PortableBackupConflictResolution],
        preferencesResolution: PortableBackupConflictResolution?
    ) throws -> PortableBackupMerge {
        guard preview.conflicts.allSatisfy({
            conflictResolutions[$0.id] != nil
        }) else {
            throw PortableBackupImportError.incompleteConflictResolution
        }
        let preferences: UserPreferences?
        switch preview.preferences {
        case .unchanged:
            preferences = nil
        case .conflict(_, let backup):
            guard let preferencesResolution else {
                throw PortableBackupImportError.incompletePreferencesResolution
            }
            preferences = preferencesResolution == .useBackup ? backup : nil
        }
        return PortableBackupMerge(
            additions: preview.additions.filter {
                selectedAdditionIDs.contains($0.id)
            },
            replacements: preview.conflicts.compactMap { conflict in
                conflictResolutions[conflict.id] == .useBackup
                    ? conflict.backup
                    : nil
            },
            preferences: preferences
        )
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
            "pinned_at", "lifecycle", "confirmed_charges_json",
            "price_changes_json", "preferences_json"
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
                    subscription.pinnedAt.map(dateString) ?? "",
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
