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
        let input = SubscriptionCreationInput(
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 0, currency: .usd),
            startDate: startDate,
            confirmedNextRenewal: startDate.addingTimeInterval(86_400),
            managementURL: nil,
            notes: ""
        )

        workspace.createSubscription(input)
        workspace.loadLibrary()

        #expect(
            workspace.creationValidationErrors[.originalAmount]
                == .mustBePositive
        )
        #expect(workspace.libraryState == .empty(.current))
    }

    @Test("Incomplete monthly input exposes field errors without creating a record")
    @MainActor
    func incompleteMonthlyInputExposesFieldErrors() {
        let repository = InMemorySubscriptionRepository()
        let startDate = Date(timeIntervalSince1970: 1_769_904_000)
        let workspace = SubscriptionWorkspace(repository: repository)
        let input = SubscriptionCreationInput(
            serviceName: "   ",
            plan: "",
            category: "\n",
            originalAmount: nil,
            startDate: startDate,
            confirmedNextRenewal: startDate.addingTimeInterval(-86_400),
            managementURL: nil,
            notes: ""
        )

        workspace.createSubscription(input)
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
        #expect(workspace.libraryState == .empty(.current))
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
        let input = SubscriptionCreationInput(
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

        creationWorkspace.createSubscription(input)

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
        guard case .loaded(.current, let subscriptions) =
            reloadedWorkspace.libraryState
        else {
            Issue.record("Expected loaded current library")
            return
        }
        #expect(subscriptions.map(\.id) == [subscriptionID])
        guard case .loaded(let loaded, let status, let nextExpectedCharge) =
            reloadedWorkspace.detailState
        else {
            Issue.record("Expected loaded subscription detail")
            return
        }
        #expect(loaded == expectedSubscription)
        #expect(status == .active)
        #expect(nextExpectedCharge != nil)
    }

    @Test("Monthly subscription text is normalized before it is saved")
    @MainActor
    func monthlySubscriptionTextIsNormalizedBeforeItIsSaved() {
        let repository = InMemorySubscriptionRepository()
        let subscriptionID = UUID(
            uuidString: "22222222-3333-4444-5555-666666666666"
        )!
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
        let workspace = SubscriptionWorkspace(
            repository: repository,
            identifierGenerator: { subscriptionID }
        )
        let input = SubscriptionCreationInput(
            serviceName: " \n Example Cloud \t",
            plan: "\t Pro \n",
            category: "\n Cloud storage ",
            originalAmount: Money(minorUnits: 1_999, currency: .cny),
            startDate: startDate,
            confirmedNextRenewal: renewalDate,
            managementURL: nil,
            notes: ""
        )

        workspace.createSubscription(input)

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
            managementURL: nil,
            notes: ""
        )
        guard case .loaded(let loaded, _, _) = workspace.detailState else {
            Issue.record("Expected loaded subscription detail")
            return
        }
        #expect(loaded == expectedSubscription)
        guard case .loaded(.current, let subscriptions) =
            workspace.libraryState
        else {
            Issue.record("Expected loaded current library")
            return
        }
        #expect(subscriptions.map(\.id) == [subscriptionID])
    }

    @Test("The in-memory repository lists subscriptions in stable identifier order")
    @MainActor
    func inMemoryRepositoryListsSubscriptionsInStableIdentifierOrder() throws {
        let repository = InMemorySubscriptionRepository()
        let firstID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let secondID = UUID(
            uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
        )!

        try repository.createSubscription(makeSubscription(id: secondID))
        try repository.createSubscription(makeSubscription(id: firstID))

        #expect(
            try repository.listSubscriptions().map(\.id)
                == [firstID, secondID]
        )
    }

    @Test("A fresh workspace loads an empty subscription library")
    @MainActor
    func freshWorkspaceLoadsEmptyLibrary() {
        let workspace = SubscriptionWorkspace(
            repository: EmptySubscriptionRepository()
        )

        workspace.loadLibrary()

        #expect(workspace.libraryState == .empty(.current))
    }

    @Test("A repository failure produces a recoverable library state")
    @MainActor
    func repositoryFailureProducesFailedState() {
        let workspace = SubscriptionWorkspace(
            repository: FailingSubscriptionRepository()
        )

        workspace.loadLibrary()

        #expect(workspace.libraryState == .failed(.current))
    }

    @Test("Existing subscriptions become observable library content")
    @MainActor
    func existingSubscriptionsBecomeLoadedState() {
        let subscription = makeSubscription(
            id: UUID(
                uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            )!
        )
        let workspace = SubscriptionWorkspace(
            repository: PopulatedSubscriptionRepository(
                subscriptions: [subscription]
            )
        )

        workspace.loadLibrary()

        guard case .loaded(.current, let subscriptions) =
            workspace.libraryState
        else {
            Issue.record("Expected loaded current library")
            return
        }
        #expect(subscriptions.map(\.id) == [subscription.id])
    }

    @Test("Current and archived scopes never mix records")
    @MainActor
    func libraryScopesRemainDisjoint() {
        let currentID = UUID(
            uuidString: "10000000-0000-0000-0000-000000000001"
        )!
        let archivedID = UUID(
            uuidString: "20000000-0000-0000-0000-000000000002"
        )!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cancelledAt = now.addingTimeInterval(-10 * 86_400)
        let accessUntil = now.addingTimeInterval(10 * 86_400)
        let calendar = utcCalendar()
        let repository = LifecycleRepository(
            subscriptions: [
                makeSubscription(id: currentID, lifecycle: .active),
                makeSubscription(
                    id: archivedID,
                    lifecycle: .cancelled(
                        cancelledAt: cancelledAt,
                        accessUntil: accessUntil
                    ),
                    isArchived: true
                ),
            ]
        )
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: { now },
            calendar: calendar
        )

        workspace.loadLibrary(scope: .current)
        guard case .loaded(.current, let current) = workspace.libraryState else {
            Issue.record("Expected current scope")
            return
        }
        #expect(current.map(\.id) == [currentID])

        workspace.loadLibrary(scope: .archived)
        guard case .loaded(.archived, let archived) = workspace.libraryState else {
            Issue.record("Expected archived scope")
            return
        }
        #expect(archived.map(\.id) == [archivedID])
        #expect(archived.first?.nextExpectedCharge == nil)
    }

    @Test("Cancelled detail has access status without a next expected charge")
    @MainActor
    func cancelledDetailOmitsNextExpectedCharge() {
        let subscriptionID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000003"
        )!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let subscription = makeSubscription(
            id: subscriptionID,
            lifecycle: .cancelled(
                cancelledAt: now.addingTimeInterval(-10 * 86_400),
                accessUntil: now.addingTimeInterval(10 * 86_400)
            )
        )
        let workspace = SubscriptionWorkspace(
            repository: LifecycleRepository(subscriptions: [subscription]),
            now: { now },
            calendar: utcCalendar()
        )

        workspace.loadSubscription(id: subscriptionID)

        guard case .loaded(
            let loaded,
            let status,
            let nextExpectedCharge
        ) = workspace.detailState else {
            Issue.record("Expected loaded detail")
            return
        }
        #expect(loaded == subscription)
        #expect(status == .cancelledWithAccess)
        #expect(nextExpectedCharge == nil)
    }

    @Test("Active detail includes a next expected charge")
    @MainActor
    func activeDetailIncludesNextExpectedCharge() {
        let subscriptionID = UUID(
            uuidString: "40000000-0000-0000-0000-000000000004"
        )!
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let subscription = makeSubscription(
            id: subscriptionID,
            lifecycle: .active
        )
        let workspace = SubscriptionWorkspace(
            repository: LifecycleRepository(subscriptions: [subscription]),
            now: { now },
            calendar: utcCalendar()
        )

        workspace.loadSubscription(id: subscriptionID)

        guard case .loaded(
            let loaded,
            let status,
            let nextExpectedCharge
        ) = workspace.detailState else {
            Issue.record("Expected loaded detail")
            return
        }
        #expect(loaded == subscription)
        #expect(status == .active)
        #expect(nextExpectedCharge != nil)
    }
}

@MainActor
private struct EmptySubscriptionRepository: SubscriptionRepository {
    func createSubscription(_ subscription: Subscription) throws {}

    func updateSubscription(_ subscription: Subscription) throws {}

    func listSubscriptions() throws -> [Subscription] {
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

    func updateSubscription(_ subscription: Subscription) throws {
        throw RepositoryError.unavailable
    }

    func listSubscriptions() throws -> [Subscription] {
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
    let subscriptions: [Subscription]

    func createSubscription(_ subscription: Subscription) throws {}

    func updateSubscription(_ subscription: Subscription) throws {}

    func listSubscriptions() throws -> [Subscription] {
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

    func updateSubscription(_ subscription: Subscription) throws {
        subscriptions[subscription.id] = subscription
    }

    func listSubscriptions() throws -> [Subscription] {
        subscriptions.values
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func subscription(id: UUID) throws -> Subscription? {
        subscriptions[id]
    }
}

@MainActor
private struct LifecycleRepository: SubscriptionRepository {
    let subscriptions: [Subscription]

    func createSubscription(_ subscription: Subscription) throws {}

    func updateSubscription(_ subscription: Subscription) throws {}

    func listSubscriptions() throws -> [Subscription] {
        subscriptions
    }

    func subscription(id: UUID) throws -> Subscription? {
        subscriptions.first { $0.id == id }
    }
}

private func makeSubscription(
    id: UUID,
    lifecycle: SubscriptionLifecycle = .active,
    isArchived: Bool = false
) -> Subscription {
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
        notes: "",
        lifecycle: lifecycle,
        isArchived: isArchived
    )
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}
