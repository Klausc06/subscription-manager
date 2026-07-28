import Foundation
import SubscriptionCore
import Testing

@Suite("Subscription workspace")
struct SubscriptionWorkspaceTests {
    @Test("A non-positive amount is rejected as an invalid fixed charge")
    @MainActor
    func nonPositiveAmountIsRejected() {
        let repository = InMemorySubscriptionRepository()
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let workspace = SubscriptionWorkspace(repository: repository)
        let input = MonthlySubscriptionCreationInput(
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 0, currency: .usd),
            startDate: startDate,
            confirmedNextRenewal: startDate.addingTimeInterval(86_400),
            managementURL: nil,
            notes: ""
        )

        workspace.createMonthlySubscription(input)
        workspace.loadLibrary()

        #expect(
            workspace.creationValidationErrors[.originalAmount]
                == .mustBePositive
        )
        #expect(workspace.libraryState == .empty)
    }

    @Test("Incomplete monthly input exposes field errors without creating a record")
    @MainActor
    func incompleteMonthlyInputExposesFieldErrors() {
        let repository = InMemorySubscriptionRepository()
        let startDate = Date(timeIntervalSince1970: 1_769_904_000)
        let workspace = SubscriptionWorkspace(repository: repository)
        let input = MonthlySubscriptionCreationInput(
            serviceName: "   ",
            plan: "",
            category: "\n",
            originalAmount: nil,
            startDate: startDate,
            confirmedNextRenewal: startDate.addingTimeInterval(-86_400),
            managementURL: nil,
            notes: ""
        )

        workspace.createMonthlySubscription(input)
        workspace.loadLibrary()

        #expect(
            workspace.creationValidationErrors == [
                .serviceName: .required,
                .plan: .required,
                .category: .required,
                .originalAmount: .required,
                .confirmedNextRenewal: .beforeStartDate,
            ]
        )
        #expect(workspace.libraryState == .empty)
    }

    @Test("A monthly subscription remains inspectable after a workspace reload")
    @MainActor
    func monthlySubscriptionRemainsInspectableAfterWorkspaceReload() {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "11111111-2222-3333-4444-555555555555"
        )!
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
        let input = MonthlySubscriptionCreationInput(
            serviceName: "Example Cloud",
            plan: "Pro",
            category: "Cloud storage",
            originalAmount: Money(minorUnits: 1_999, currency: .cny),
            startDate: startDate,
            confirmedNextRenewal: renewalDate,
            managementURL: URL(string: "https://example.com/account"),
            notes: "Work files"
        )
        let creationWorkspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID }
        )

        creationWorkspace.createMonthlySubscription(input)

        let reloadedWorkspace = SubscriptionWorkspace(repository: repository)
        reloadedWorkspace.loadLibrary()
        reloadedWorkspace.loadSubscription(id: subscriptionID)

        let expectedSubscription = Subscription(
            id: subscriptionID,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(subscriptionID.uuidString)"
            ),
            serviceName: "Example Cloud",
            plan: "Pro",
            category: "Cloud storage",
            originalAmount: Money(minorUnits: 1_999, currency: .cny),
            billingCycle: .monthly,
            startDate: startDate,
            confirmedNextRenewal: renewalDate,
            managementURL: URL(string: "https://example.com/account"),
            notes: "Work files"
        )
        #expect(
            reloadedWorkspace.libraryState
                == .loaded([SubscriptionSummary(subscription: expectedSubscription)])
        )
        #expect(
            reloadedWorkspace.detailState == .loaded(expectedSubscription)
        )
    }

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
            subscription: makeSubscription(
                id: UUID(
                    uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
                )!
            )
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
    func createSubscription(_ subscription: Subscription) throws {}

    func listSubscriptions() throws -> [SubscriptionSummary] {
        []
    }

    func subscription(id: UUID) throws -> Subscription? {
        nil
    }
}

@MainActor
private struct FailingSubscriptionRepository: SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws {
        throw RepositoryError.unavailable
    }

    func listSubscriptions() throws -> [SubscriptionSummary] {
        throw RepositoryError.unavailable
    }

    func subscription(id: UUID) throws -> Subscription? {
        throw RepositoryError.unavailable
    }

    private enum RepositoryError: Error {
        case unavailable
    }
}

@MainActor
private struct PopulatedSubscriptionRepository: SubscriptionRepository {
    let subscriptions: [SubscriptionSummary]

    func createSubscription(_ subscription: Subscription) throws {}

    func listSubscriptions() throws -> [SubscriptionSummary] {
        subscriptions
    }

    func subscription(id: UUID) throws -> Subscription? {
        nil
    }
}

@MainActor
private final class InMemorySubscriptionRepository: SubscriptionRepository {
    private var subscriptions: [UUID: Subscription] = [:]

    func createSubscription(_ subscription: Subscription) throws {
        subscriptions[subscription.id] = subscription
    }

    func listSubscriptions() throws -> [SubscriptionSummary] {
        subscriptions.values.map(SubscriptionSummary.init(subscription:))
    }

    func subscription(id: UUID) throws -> Subscription? {
        subscriptions[id]
    }
}

private func makeSubscription(id: UUID) -> Subscription {
    let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
    let amount = Money(minorUnits: 999, currency: .usd)
    return Subscription(
        id: id,
        serviceIdentity: ServiceIdentity(rawValue: "manual:\(id.uuidString)"),
        serviceName: "Example",
        plan: "Standard",
        category: "Other",
        originalAmount: amount,
        billingCycle: .monthly,
        startDate: Date(timeIntervalSince1970: 1_767_225_600),
        confirmedNextRenewal: renewalDate,
        managementURL: nil,
        notes: ""
    )
}
