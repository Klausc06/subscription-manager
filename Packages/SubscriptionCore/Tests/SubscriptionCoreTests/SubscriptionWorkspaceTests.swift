import Foundation
import SubscriptionCore
import Testing

@Suite("Subscription workspace")
struct SubscriptionWorkspaceTests {
    @Test("A fresh workspace loads an empty subscription library")
    @MainActor
    func freshWorkspaceLoadsEmptyLibrary() {
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository()
        )

        workspace.loadLibrary()

        #expect(workspace.libraryState == .empty)
    }

    @Test("A repository failure produces a recoverable library state")
    @MainActor
    func repositoryFailureProducesFailedState() {
        let workspace = SubscriptionWorkspace(
            repository: FailingSubscriptionRepository()
        )

        workspace.loadLibrary()

        #expect(workspace.libraryState == .failed)
    }

    @Test("Existing subscriptions become observable library content")
    @MainActor
    func existingSubscriptionsBecomeLoadedState() {
        let subscription = SubscriptionSummary(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        let workspace = SubscriptionWorkspace(
            repository: PopulatedSubscriptionRepository(
                subscriptions: [subscription]
            )
        )

        workspace.loadLibrary()

        #expect(workspace.libraryState == .loaded([subscription]))
    }
}

@MainActor
private struct EmptySubscriptionRepository: SubscriptionRepository {
    func listSubscriptions() throws -> [SubscriptionSummary] {
        []
    }
}

@MainActor
private struct FailingSubscriptionRepository: SubscriptionRepository {
    func listSubscriptions() throws -> [SubscriptionSummary] {
        throw RepositoryError.unavailable
    }

    private enum RepositoryError: Error {
        case unavailable
    }
}

@MainActor
private struct PopulatedSubscriptionRepository: SubscriptionRepository {
    let subscriptions: [SubscriptionSummary]

    func listSubscriptions() throws -> [SubscriptionSummary] {
        subscriptions
    }
}
