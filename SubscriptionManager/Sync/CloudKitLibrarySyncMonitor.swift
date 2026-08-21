import CloudKit
import CoreData
import Foundation
import SubscriptionCore

final class CloudKitLibrarySyncMonitor: LibrarySyncMonitor, @unchecked Sendable {
    // A recent FIFO window keeps terminal-event deduplication bounded without
    // retaining an unbounded history of CloudKit event IDs.
    private static let processedEventCapacity = 256
    private let accountStatus: @Sendable () async throws -> CKAccountStatus
    private let stateLock = NSLock()
    private var hasCompletedSync = false
    private var hasSyncFailure = false
    private var processedEventIDs = Set<UUID>()
    private var processedEventOrder = [UUID]()
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
                    if hasSyncFailure {
                        return .requiresAttention
                    }
                    return hasCompletedSync ? .current : .synchronizing
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
            guard rememberProcessedEventID(id) else {
                return nil
            }
            hasCompletedSync = true
            hasSyncFailure = false
            return workspaceReloadHandler
        }
        await handler?()
    }

    func notifySuccessfulExport(id: UUID) {
        notifySuccessfulEvent(id: id)
    }

    func notifySuccessfulSetup(id: UUID) {
        notifySuccessfulEvent(id: id)
    }

    private func notifySuccessfulEvent(id: UUID) {
        stateLock.withLock {
            guard rememberProcessedEventID(id) else { return }
            hasCompletedSync = true
            hasSyncFailure = false
        }
    }

    func notifyFailedEvent(id: UUID) {
        stateLock.withLock {
            guard rememberProcessedEventID(id) else { return }
            hasSyncFailure = true
        }
    }

    private func rememberProcessedEventID(_ id: UUID) -> Bool {
        guard !processedEventIDs.contains(id) else {
            return false
        }
        if processedEventIDs.count == Self.processedEventCapacity {
            let evictedID = processedEventOrder.removeFirst()
            processedEventIDs.remove(evictedID)
        }
        processedEventIDs.insert(id)
        processedEventOrder.append(id)
        return true
    }

    private func handle(notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event,
        event.endDate != nil
        else {
            return
        }
        guard event.succeeded else {
            notifyFailedEvent(id: event.identifier)
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
            notifySuccessfulSetup(id: event.identifier)
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
