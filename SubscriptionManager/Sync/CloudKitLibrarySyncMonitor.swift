import CloudKit
import CoreData
import Foundation
import SubscriptionCore

final class CloudKitLibrarySyncMonitor: LibrarySyncMonitor, @unchecked Sendable {
    private let accountStatus: @Sendable () async throws -> CKAccountStatus
    private let stateLock = NSLock()
    private var hasCompletedSync = false
    private var processedEventIDs = Set<UUID>()
    private var workspaceReloadHandler: (@Sendable () -> Void)?
    private var eventObserver: NSObjectProtocol?

    init(
        accountStatus: @escaping @Sendable () async throws -> CKAccountStatus,
        onRemoteImport: @escaping @Sendable () -> Void = {}
    ) {
        self.accountStatus = accountStatus
        workspaceReloadHandler = onRemoteImport
        eventObserver = nil
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handle(notification: notification)
        }
    }

    convenience init(
        container: CKContainer = .default(),
        onRemoteImport: @escaping @Sendable () -> Void = {}
    ) {
        self.init(
            accountStatus: { try await container.accountStatus() },
            onRemoteImport: onRemoteImport
        )
    }

    deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
    }

    func refreshStatus() async -> LibrarySyncStatus {
        do {
            let status = try await accountStatus()
            switch status {
            case .available:
                return stateLock.withLock {
                    hasCompletedSync ? .current : .synchronizing
                }
            case .noAccount:
                return .signedOut
            case .restricted, .couldNotDetermine, .temporarilyUnavailable:
                return .localOnly
            @unknown default:
                return .localOnly
            }
        } catch {
            return .requiresAttention
        }
    }

    func setWorkspaceReloadHandler(
        _ handler: @escaping @Sendable () -> Void
    ) {
        stateLock.withLock {
            workspaceReloadHandler = handler
        }
    }

    func notifyRemoteImport(id: UUID) {
        let handler: (@Sendable () -> Void)? = stateLock.withLock {
            guard processedEventIDs.insert(id).inserted else {
                return nil
            }
            hasCompletedSync = true
            return workspaceReloadHandler
        }
        handler?()
    }

    private func handle(notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event,
        event.type == .import,
        event.succeeded,
        event.endDate != nil
        else {
            return
        }
        notifyRemoteImport(id: event.identifier)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
