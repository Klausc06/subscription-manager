import Foundation
import Observation

@MainActor
public protocol SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws
    func updateSubscription(_ subscription: Subscription) throws
    func deleteSubscription(id: UUID) throws
    func listSubscriptions() throws -> [Subscription]
    func subscription(id: UUID) throws -> Subscription?
}

/// Adopted by repositories that silently drop unreadable records during
/// loads so callers can surface how much of the library was not returned.
@MainActor
public protocol SkippedRecordReporting {
    var skippedRecordCountAfterLastLoad: Int { get }
}

/// A portable backup together with a count of unreadable local records that
/// were skipped while reading the library for that export.
public struct PortableBackupExport: Equatable, Sendable {
    public let backup: PortableBackup
    public let skippedRecordCount: Int

    public init(backup: PortableBackup, skippedRecordCount: Int) {
        self.backup = backup
        self.skippedRecordCount = skippedRecordCount
    }
}

public enum LibrarySyncStatus: Equatable, Sendable {
    case notLoaded
    case localOnly
    case synchronizing
    case current
    case signedOut
    case requiresAttention
}

public protocol LibrarySyncMonitor: Sendable {
    func refreshStatus() async -> LibrarySyncStatus
}
