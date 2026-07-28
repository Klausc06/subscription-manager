import CloudKit
import SubscriptionCore

struct CloudKitLibrarySyncMonitor: LibrarySyncMonitor {
    private let accountStatus: @Sendable () async throws -> CKAccountStatus

    init(
        accountStatus: @escaping @Sendable () async throws -> CKAccountStatus
    ) {
        self.accountStatus = accountStatus
    }

    init(container: CKContainer = .default()) {
        accountStatus = { try await container.accountStatus() }
    }

    func refreshStatus() async -> LibrarySyncStatus {
        do {
            return switch try await accountStatus() {
            case .available:
                .current
            case .noAccount:
                .signedOut
            case .restricted, .couldNotDetermine, .temporarilyUnavailable:
                .localOnly
            @unknown default:
                .localOnly
            }
        } catch {
            return .requiresAttention
        }
    }
}
