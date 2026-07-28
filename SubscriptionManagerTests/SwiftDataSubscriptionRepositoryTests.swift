import Foundation
import SwiftData
import SubscriptionCore
import Testing
@testable import SubscriptionManager

@Suite("SwiftData subscription repository")
struct SwiftDataSubscriptionRepositoryTests {
    private enum StoreInitializationFailure: Error {
        case unavailable
    }

    @Test("A store initialization failure remains renderable")
    @MainActor
    func storeInitializationFailureIsRecoverable() {
        let startupState = AppDependencies.make {
            throw StoreInitializationFailure.unavailable
        }

        guard case .failed(let failure) = startupState else {
            Issue.record("Expected a recoverable startup failure")
            return
        }

        #expect(failure.underlyingError is StoreInitializationFailure)
    }

    @Test("A fresh in-memory store exposes an empty library")
    @MainActor
    func freshStoreIsEmpty() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )

        let subscriptions = try repository.listSubscriptions()

        #expect(subscriptions.isEmpty)
    }

    @Test("A created subscription reloads with every source field intact")
    @MainActor
    func createdSubscriptionReloadsWithEverySourceFieldIntact() throws {
        let subscriptionID = UUID(
            uuidString: "6FD01C11-CE25-4987-9C6F-02B46F080D63"
        )!
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let renewalDate = Date(timeIntervalSince1970: 1_769_904_000)
        let expectedSubscription = Subscription(
            id: subscriptionID,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(subscriptionID.uuidString)"
            ),
            serviceName: "Example Cloud",
            plan: "Professional",
            category: "Cloud storage",
            originalAmount: Money(
                minorUnits: 9_007_199_254_740_993,
                currency: .cny
            ),
            billingCycle: .monthly,
            startDate: startDate,
            confirmedNextRenewal: renewalDate,
            managementURL: URL(string: "https://example.com/account?lang=zh"),
            notes: "工作文件"
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let creationRepository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        try creationRepository.createSubscription(expectedSubscription)

        let reloadedRepository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        let reloadedSubscription = try reloadedRepository.subscription(
            id: subscriptionID
        )

        #expect(reloadedSubscription == expectedSubscription)
        #expect(
            reloadedSubscription?.firstExpectedCharge
                == ExpectedCharge(
                    subscriptionID: subscriptionID,
                    scheduledDate: renewalDate,
                    amount: Money(
                        minorUnits: 9_007_199_254_740_993,
                        currency: .cny
                    )
                )
        )
    }

    @Test("A USD subscription with empty optional text appears in the library")
    @MainActor
    func usdSubscriptionWithEmptyOptionalTextAppearsInLibrary() throws {
        let subscription = Subscription(
            id: UUID(
                uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            )!,
            serviceIdentity: ServiceIdentity(rawValue: "catalog:example"),
            serviceName: "Example Video",
            plan: "Standard",
            category: "Entertainment",
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: Date(
                timeIntervalSince1970: 1_769_904_000
            ),
            managementURL: nil,
            notes: ""
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        try repository.createSubscription(subscription)

        let subscriptions = try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).listSubscriptions()

        #expect(
            subscriptions == [SubscriptionSummary(subscription: subscription)]
        )
    }

    @Test("Looking up an unknown identifier returns no subscription")
    @MainActor
    func unknownIdentifierReturnsNoSubscription() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )

        let subscription = try repository.subscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )

        #expect(subscription == nil)
    }

    @Test("A walking-skeleton record remains readable after schema expansion")
    @MainActor
    func walkingSkeletonRecordRemainsReadable() throws {
        let subscriptionID = UUID(
            uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
        )!
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        container.mainContext.insert(SubscriptionRecord(id: subscriptionID))
        try container.mainContext.save()
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )

        let subscription = try repository.subscription(id: subscriptionID)

        #expect(subscription?.id == subscriptionID)
        #expect(
            subscription?.serviceIdentity
                == ServiceIdentity(
                    rawValue: "manual:\(subscriptionID.uuidString)"
                )
        )
        #expect(subscription?.originalAmount == Money(
            minorUnits: 0,
            currency: .usd
        ))
        #expect(subscription?.billingCycle == .monthly)
        #expect(subscription?.managementURL == nil)
        #expect(subscription?.notes == "")
    }

    @Test("UI testing launches use separate in-memory libraries")
    @MainActor
    func uiTestingLaunchesUseSeparateInMemoryLibraries() {
        let input = MonthlySubscriptionCreationInput(
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: Date(
                timeIntervalSince1970: 1_769_904_000
            ),
            managementURL: nil,
            notes: ""
        )

        guard case .ready(let firstLaunch) = AppDependencies.live(
            arguments: ["SubscriptionManager", "--ui-testing"]
        ) else {
            Issue.record("Expected the first UI testing launch to be ready")
            return
        }
        firstLaunch.workspace.createMonthlySubscription(input)

        guard case .ready(let secondLaunch) = AppDependencies.live(
            arguments: ["SubscriptionManager", "--ui-testing"]
        ) else {
            Issue.record("Expected the second UI testing launch to be ready")
            return
        }
        secondLaunch.workspace.loadLibrary()

        #expect(secondLaunch.workspace.libraryState == .empty)
    }

    @Test("A named UI testing store survives an application relaunch")
    @MainActor
    func namedUITestingStoreSurvivesApplicationRelaunch() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "SubscriptionManagerTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        let arguments = [
            "SubscriptionManager",
            "--ui-testing",
            "--ui-testing-store",
            "relaunch-contract",
        ]
        let input = MonthlySubscriptionCreationInput(
            serviceName: "Example",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 1_299, currency: .usd),
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: Date(
                timeIntervalSince1970: 1_769_904_000
            ),
            managementURL: nil,
            notes: ""
        )

        do {
            guard case .ready(let firstLaunch) = AppDependencies.live(
                arguments: arguments,
                storeDirectory: storeDirectory
            ) else {
                Issue.record("Expected the first disk-backed launch to be ready")
                return
            }
            firstLaunch.workspace.createMonthlySubscription(input)
        }

        guard case .ready(let relaunchedApp) = AppDependencies.live(
            arguments: arguments,
            storeDirectory: storeDirectory
        ) else {
            Issue.record("Expected the relaunched app to reopen its store")
            return
        }
        relaunchedApp.workspace.loadLibrary()

        guard case .loaded(let subscriptions) =
            relaunchedApp.workspace.libraryState
        else {
            Issue.record("Expected the saved subscription after relaunch")
            return
        }
        #expect(subscriptions.map(\.serviceName) == ["Example"])
    }
}
