import CloudKit
import CoreData
import Foundation
import SubscriptionCore

final class CloudKitLibrarySyncMonitor: LibrarySyncMonitor, @unchecked Sendable {
    private let accountStatus: @Sendable () async throws -> CKAccountStatus
    private let stateLock = NSLock()
    private var hasCompletedSync = false
    private var processedEventIDs = Set<UUID>()
    private var workspaceReloadHandler: (@Sendable () async -> Void)?
    private var eventObserver: NSObjectProtocol?

    init(
        accountStatus: @escaping @Sendable () async throws -> CKAccountStatus,
        onRemoteImport: @escaping @Sendable () async -> Void = {}
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
        onRemoteImport: @escaping @Sendable () async -> Void = {}
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
        _ handler: @escaping @Sendable () async -> Void
    ) {
        stateLock.withLock {
            workspaceReloadHandler = handler
        }
    }

    func notifyRemoteImport(id: UUID) async {
        let handler: (@Sendable () async -> Void)? = stateLock.withLock {
            guard processedEventIDs.insert(id).inserted else {
                return nil
            }
            hasCompletedSync = true
            return workspaceReloadHandler
        }
        await handler?()
    }

    func notifySuccessfulExport(id: UUID) {
        stateLock.withLock {
            guard processedEventIDs.insert(id).inserted else { return }
            hasCompletedSync = true
        }
    }

    private func handle(notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event,
        event.succeeded,
        event.endDate != nil
        else {
            return
        }
        switch event.type {
        case .import:
            let eventID = event.identifier
            Task { [weak self] in
                await self?.notifyRemoteImport(id: eventID)
            }
        case .export:
            notifySuccessfulExport(id: event.identifier)
        case .setup:
            break
        @unknown default:
            break
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
