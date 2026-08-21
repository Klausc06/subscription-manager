import Foundation

public struct WidgetRenewalSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let subscriptionID: UUID
    public let serviceName: String
    public let renewalDate: Date
    public let amountDescription: String?
    public let isRateStale: Bool

    public var id: UUID { subscriptionID }

    public init(
        subscriptionID: UUID,
        serviceName: String,
        renewalDate: Date,
        amountDescription: String?,
        isRateStale: Bool
    ) {
        self.subscriptionID = subscriptionID
        self.serviceName = serviceName
        self.renewalDate = renewalDate
        self.amountDescription = amountDescription
        self.isRateStale = isRateStale
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let generatedAt: Date
    public let nextRenewal: WidgetRenewalSnapshot?

    public init(generatedAt: Date, nextRenewal: WidgetRenewalSnapshot?) {
        version = Self.currentVersion
        self.generatedAt = generatedAt
        self.nextRenewal = nextRenewal
    }
}

/// A deliberately small shared-store boundary for WidgetKit extensions.
///
/// The store contains only a derived renewal snapshot. It never opens the
/// Subscription Library or performs a network request from the extension.
public final class WidgetSnapshotStore {
    public static let appGroupIdentifier =
        "group.com.klausc06.SubscriptionManager"
    public static let snapshotKey = "subscription-manager.widget-snapshot"
    public static let renewalWidgetKind =
        "com.klausc06.SubscriptionManager.renewal"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public convenience init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }
        self.init(defaults: defaults)
    }

    @discardableResult
    public func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let data = try? encoder.encode(snapshot) else { return false }
        defaults.set(data, forKey: Self.snapshotKey)
        return true
    }

    public func read() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey),
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion
        else {
            return nil
        }
        return snapshot
    }
}

@MainActor
public protocol WidgetSnapshotPublishing {
    func publish(_ snapshot: WidgetSnapshot)
}

public enum WidgetPrivacyMode: Equatable, Sendable {
    case standard
    case redacted
}

public struct WidgetPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let amountDescription: String?
    public let deepLink: URL?

    public init(
        title: String,
        subtitle: String,
        amountDescription: String?,
        deepLink: URL?
    ) {
        self.title = title
        self.subtitle = subtitle
        self.amountDescription = amountDescription
        self.deepLink = deepLink
    }
}

public struct WidgetPresentationBuilder: Sendable {
    public init() {}

    public func makePresentation(
        snapshot: WidgetSnapshot,
        privacy: WidgetPrivacyMode,
        dateFormatter: (Date) -> String
    ) -> WidgetPresentation {
        guard let renewal = snapshot.nextRenewal else {
            return WidgetPresentation(
                title: "No Upcoming Renewals",
                subtitle: "Add a subscription to see it here.",
                amountDescription: nil,
                deepLink: URL(string: "subscription-manager://subscriptions")
            )
        }
        let subtitle = renewal.isRateStale
            ? "Rates are stale · \(dateFormatter(renewal.renewalDate))"
            : dateFormatter(renewal.renewalDate)
        return WidgetPresentation(
            title: renewal.serviceName,
            subtitle: subtitle,
            amountDescription: privacy == .standard
                ? renewal.amountDescription
                : nil,
            deepLink: URL(
                string: "subscription-manager://subscription/"
                    + renewal.subscriptionID.uuidString
            )
        )
    }
}
