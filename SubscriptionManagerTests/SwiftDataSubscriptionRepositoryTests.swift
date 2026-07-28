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

    private enum SaveFailure: Error {
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

    @Test("A custom schedule and confirmed history survive a repository reload")
    @MainActor
    func customScheduleAndConfirmedHistoryRoundTrip() throws {
        let subscriptionID = UUID(
            uuidString: "5D25D54C-218D-4BE7-BBB1-64FCE271C9B7"
        )!
        let anchor = Date(timeIntervalSince1970: 1_758_837_600)
        let confirmedCharge = ConfirmedCharge(
            id: UUID(
                uuidString: "BA665353-ECDA-4C19-B23A-87B71EB188D8"
            )!,
            chargedDate: Date(timeIntervalSince1970: 1_756_159_200),
            amount: Money(minorUnits: 2_999, currency: .cny)
        )
        let expectedSubscription = Subscription(
            id: subscriptionID,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(subscriptionID.uuidString)"
            ),
            serviceName: "Example Cloud",
            plan: "Flexible",
            category: "Cloud storage",
            originalAmount: Money(minorUnits: 3_199, currency: .cny),
            billingSchedule: FixedBillingSchedule(
                interval: .custom(value: 5, unit: .week),
                renewalAnchor: anchor,
                timeZoneIdentifier: "Asia/Shanghai"
            ),
            startDate: Date(timeIntervalSince1970: 1_745_715_600),
            managementURL: nil,
            notes: "",
            confirmedCharges: [confirmedCharge]
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).createSubscription(expectedSubscription)

        let reloaded = try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).subscription(id: subscriptionID)

        #expect(reloaded == expectedSubscription)
    }

    @Test("Updating a subscription mutates one record and keeps confirmed history")
    @MainActor
    func updateMutatesOneRecordAndKeepsConfirmedHistory() throws {
        let subscriptionID = UUID(
            uuidString: "0273738B-1AA8-4A45-83F4-E06A0447D7EE"
        )!
        let confirmedCharge = ConfirmedCharge(
            id: UUID(
                uuidString: "2E7AA6C6-0208-4AE4-9327-CC1927D91468"
            )!,
            chargedDate: Date(timeIntervalSince1970: 1_756_159_200),
            amount: Money(minorUnits: 999, currency: .usd)
        )
        let original = Subscription(
            id: subscriptionID,
            serviceIdentity: ServiceIdentity(rawValue: "catalog:example"),
            serviceName: "Example",
            plan: "Monthly",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .monthly,
                renewalAnchor: Date(timeIntervalSince1970: 1_758_837_600),
                timeZoneIdentifier: "America/New_York"
            ),
            startDate: Date(timeIntervalSince1970: 1_745_715_600),
            managementURL: nil,
            notes: "",
            confirmedCharges: [confirmedCharge]
        )
        let edited = Subscription(
            id: subscriptionID,
            serviceIdentity: original.serviceIdentity,
            serviceName: "Example Plus",
            plan: "Annual",
            category: original.category,
            originalAmount: Money(minorUnits: 9_999, currency: .usd),
            billingSchedule: FixedBillingSchedule(
                interval: .yearly,
                renewalAnchor: Date(timeIntervalSince1970: 1_761_516_000),
                timeZoneIdentifier: "America/New_York"
            ),
            startDate: original.startDate,
            managementURL: nil,
            notes: "Updated",
            confirmedCharges: original.confirmedCharges
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        try repository.createSubscription(original)

        try repository.updateSubscription(edited)

        #expect(try repository.subscription(id: subscriptionID) == edited)
        #expect(try repository.listSubscriptions().count == 1)
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

    @Test("A failed save does not leak its subscription into a later retry")
    @MainActor
    func failedSaveDoesNotLeakIntoLaterRetry() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        var saveAttempt = 0
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container,
            save: { modelContext in
                saveAttempt += 1
                if saveAttempt == 1 {
                    throw SaveFailure.unavailable
                }
                try modelContext.save()
            }
        )
        let failedSubscription = Subscription(
            id: UUID(
                uuidString: "10000000-0000-0000-0000-000000000001"
            )!,
            serviceIdentity: ServiceIdentity(rawValue: "manual:failed"),
            serviceName: "Failed attempt",
            plan: "Monthly",
            category: "Other",
            originalAmount: Money(minorUnits: 499, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: Date(
                timeIntervalSince1970: 1_769_904_000
            ),
            managementURL: nil,
            notes: ""
        )
        let retriedSubscription = Subscription(
            id: UUID(
                uuidString: "20000000-0000-0000-0000-000000000002"
            )!,
            serviceIdentity: ServiceIdentity(rawValue: "manual:retry"),
            serviceName: "Successful retry",
            plan: "Monthly",
            category: "Other",
            originalAmount: Money(minorUnits: 799, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: Date(
                timeIntervalSince1970: 1_769_904_000
            ),
            managementURL: nil,
            notes: ""
        )

        #expect(throws: SaveFailure.self) {
            try repository.createSubscription(failedSubscription)
        }
        try repository.createSubscription(retriedSubscription)

        let subscriptions = try repository.listSubscriptions()
        #expect(
            subscriptions
                == [SubscriptionSummary(subscription: retriedSubscription)]
        )
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
        #expect(
            subscription?.billingSchedule.timeZoneIdentifier
                == TimeZone.autoupdatingCurrent.identifier
        )
        #expect(subscription?.confirmedCharges == [])
        #expect(subscription?.managementURL == nil)
        #expect(subscription?.notes == "")
    }

    @Test("A migrated monthly record backfills its billing time zone once")
    @MainActor
    func migratedRecordBackfillsBillingTimeZoneOnce() throws {
        let subscriptionID = UUID(
            uuidString: "9A69A77D-C15A-4B3C-B3BD-F4C27C584113"
        )!
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        container.mainContext.insert(SubscriptionRecord(id: subscriptionID))
        try container.mainContext.save()

        let firstRelaunch = SwiftDataSubscriptionRepository(
            modelContainer: container,
            defaultBillingTimeZone: {
                TimeZone(identifier: "America/Los_Angeles")!
            }
        )
        let migrated = try firstRelaunch.subscription(id: subscriptionID)

        let secondRelaunch = SwiftDataSubscriptionRepository(
            modelContainer: container,
            defaultBillingTimeZone: {
                TimeZone(identifier: "Asia/Shanghai")!
            }
        )
        let reloaded = try secondRelaunch.subscription(id: subscriptionID)

        #expect(
            migrated?.billingSchedule.timeZoneIdentifier
                == "America/Los_Angeles"
        )
        #expect(
            reloaded?.billingSchedule.timeZoneIdentifier
                == "America/Los_Angeles"
        )
    }

    @Test("Migration reconstructs a clamped monthly renewal anchor")
    @MainActor
    func migrationReconstructsClampedMonthlyAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startDate = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2025,
                    month: 1,
                    day: 31,
                    hour: 12
                )
            )
        )
        let nextRenewal = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2025,
                    month: 2,
                    day: 28,
                    hour: 12
                )
            )
        )
        let subscriptionID = UUID(
            uuidString: "D531C53E-E65E-4B08-A388-8944218B6D1C"
        )!
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        container.mainContext.insert(
            SubscriptionRecord(
                id: subscriptionID,
                startDate: startDate,
                confirmedNextRenewal: nextRenewal
            )
        )
        try container.mainContext.save()
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container,
            defaultBillingTimeZone: {
                TimeZone(identifier: "UTC")!
            }
        )

        let migrated = try repository.subscription(id: subscriptionID)

        #expect(migrated?.billingSchedule.renewalAnchor == startDate)
        #expect(migrated?.confirmedNextRenewal == nextRenewal)
        #expect(
            try container.mainContext.fetch(
                FetchDescriptor<SubscriptionRecord>()
            ).first?.renewalAnchor == startDate
        )
    }

    @Test("UI testing launches use separate in-memory libraries")
    @MainActor
    func uiTestingLaunchesUseSeparateInMemoryLibraries() {
        let input = SubscriptionCreationInput(
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
        firstLaunch.workspace.createSubscription(input)

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
        let input = SubscriptionCreationInput(
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
            firstLaunch.workspace.createSubscription(input)
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
