import Foundation
import Observation

public struct SubscriptionSummary: Equatable, Identifiable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public enum SubscriptionLibraryState: Equatable, Sendable {
    case loading
    case empty
    case loaded([SubscriptionSummary])
    case failed
}

@MainActor
public protocol SubscriptionRepository {
    func listSubscriptions() throws -> [SubscriptionSummary]
}

@MainActor
@Observable
public final class SubscriptionWorkspace {
    public private(set) var libraryState: SubscriptionLibraryState = .loading

    private let repository: any SubscriptionRepository

    public init(repository: any SubscriptionRepository) {
        self.repository = repository
    }

    public func loadLibrary() {
        do {
            let subscriptions = try repository.listSubscriptions()
            if subscriptions.isEmpty {
                libraryState = .empty
            } else {
                libraryState = .loaded(subscriptions)
            }
        } catch {
            libraryState = .failed
        }
    }
}
