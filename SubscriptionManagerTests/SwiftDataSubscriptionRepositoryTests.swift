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
        #expect(reloadedSubscription?.confirmedNextRenewal == renewalDate)
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

        #expect(subscriptions == [subscription])
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
        #expect(subscriptions == [retriedSubscription])
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

    @Test("Legacy rows load as active and unarchived")
    @MainActor
    func legacyRowsLoadAsActiveAndUnarchived() throws {
        let subscriptionID = UUID(
            uuidString: "6A25C407-3C96-45A9-83EC-7EE52D62F16F"
        )!
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        container.mainContext.insert(SubscriptionRecord(id: subscriptionID))
        try container.mainContext.save()

        let subscription = try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).subscription(id: subscriptionID)

        #expect(subscription?.lifecycle == .active)
        #expect(subscription?.isArchived == false)
    }

    @Test(
        "A pre-TB-04 disk store survives production migration and reopen"
    )
    @MainActor
    func preTB04DiskStoreSurvivesProductionMigrationAndReopen() throws {
        let storeRoot = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerLegacy-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer {
            try? FileManager.default.removeItem(at: storeRoot)
        }
        let token = "pre-tb04"
        let storeDirectory = storeRoot.appending(
            path: "SubscriptionManagerUITests",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let storeURL = storeDirectory.appending(path: "\(token).store")
        let subscriptionID = UUID(
            uuidString: "04A11CE0-0000-4000-8000-000000000004"
        )!
        let charge = ConfirmedCharge(
            id: UUID(
                uuidString: "04C0FFEE-0000-4000-8000-000000000004"
            )!,
            chargedDate: Date(timeIntervalSince1970: 1_768_003_200),
            amount: Money(minorUnits: 12_345, currency: .cny)
        )
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let renewalAnchor = Date(timeIntervalSince1970: 1_767_312_000)
        let nextRenewal = Date(timeIntervalSince1970: 1_769_904_000)
        let managementURL = URL(
            string: "https://example.com/manage/pre-tb04"
        )!

        do {
            let legacySchema = Schema([
                PreTB04Schema.SubscriptionRecord.self
            ])
            let legacyConfiguration = ModelConfiguration(
                "UITesting-\(token)",
                schema: legacySchema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [legacyConfiguration]
            )
            legacyContainer.mainContext.insert(
                PreTB04Schema.SubscriptionRecord(
                    id: subscriptionID,
                    serviceIdentityRawValue: "catalog:legacy-service",
                    serviceName: "Legacy Service",
                    plan: "Three Week Plan",
                    category: "Productivity",
                    originalMinorUnits: 12_345,
                    currencyRawValue: "CNY",
                    billingCycleRawValue: "custom",
                    billingIntervalValue: 3,
                    billingIntervalUnitRawValue: "week",
                    billingTimeZoneIdentifier: "Asia/Shanghai",
                    startDate: startDate,
                    renewalAnchor: renewalAnchor,
                    confirmedNextRenewal: nextRenewal,
                    managementURLString: managementURL.absoluteString,
                    notes: "Preserve legacy notes",
                    confirmedChargesData: try JSONEncoder().encode([charge])
                )
            )
            try legacyContainer.mainContext.save()
        }

        let arguments = [
            "SubscriptionManager",
            "--ui-testing",
            "--ui-testing-store",
            token,
        ]
        for launchNumber in 1 ... 2 {
            guard case .ready(let dependencies) = AppDependencies.live(
                arguments: arguments,
                storeDirectory: storeRoot
            ) else {
                Issue.record(
                    "Expected production container launch \(launchNumber)"
                )
                return
            }
            dependencies.workspace.loadSubscription(id: subscriptionID)
            guard case .loaded(let subscription, _, _) =
                dependencies.workspace.detailState
            else {
                Issue.record(
                    "Expected migrated detail on launch \(launchNumber)"
                )
                return
            }
            #expect(subscription.id == subscriptionID)
            #expect(
                subscription.serviceIdentity
                    == ServiceIdentity(rawValue: "catalog:legacy-service")
            )
            #expect(subscription.serviceName == "Legacy Service")
            #expect(subscription.plan == "Three Week Plan")
            #expect(subscription.category == "Productivity")
            #expect(
                subscription.originalAmount
                    == Money(minorUnits: 12_345, currency: .cny)
            )
            #expect(
                subscription.billingSchedule
                    == FixedBillingSchedule(
                        interval: .custom(value: 3, unit: .week),
                        renewalAnchor: renewalAnchor,
                        timeZoneIdentifier: "Asia/Shanghai"
                    )
            )
            #expect(subscription.startDate == startDate)
            #expect(subscription.confirmedNextRenewal == nextRenewal)
            #expect(subscription.managementURL == managementURL)
            #expect(subscription.notes == "Preserve legacy notes")
            #expect(subscription.confirmedCharges == [charge])
            #expect(subscription.lifecycle == .active)
            #expect(subscription.isArchived == false)
        }
    }

    @Test("Trial active and cancelled lifecycle representations round trip")
    @MainActor
    func lifecycleRepresentationsRoundTrip() throws {
        let trialDate = Date(timeIntervalSince1970: 1_768_003_200)
        let cancelledAt = Date(timeIntervalSince1970: 1_768_089_600)
        let accessUntil = Date(timeIntervalSince1970: 1_770_768_000)
        let active = makeSubscription(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            lifecycle: .active,
            isArchived: true
        )
        let trial = makeSubscription(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            lifecycle: .trial(firstPaidChargeAt: trialDate),
            isArchived: false
        )
        let cancelled = makeSubscription(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
            lifecycle: .cancelled(
                cancelledAt: cancelledAt,
                accessUntil: accessUntil
            ),
            isArchived: true
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        try repository.createSubscription(active)
        try repository.createSubscription(trial)
        try repository.createSubscription(cancelled)

        let reloaded = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        let reloadedActive = try reloaded.subscription(id: active.id)
        let reloadedTrial = try reloaded.subscription(id: trial.id)
        let reloadedCancelled = try reloaded.subscription(id: cancelled.id)

        #expect(reloadedActive?.lifecycle == .active)
        #expect(reloadedActive?.isArchived == true)
        #expect(
            reloadedTrial?.lifecycle
                == .trial(firstPaidChargeAt: trialDate)
        )
        #expect(reloadedTrial?.isArchived == false)
        #expect(
            reloadedCancelled?.lifecycle
                == .cancelled(
                    cancelledAt: cancelledAt,
                    accessUntil: accessUntil
                )
        )
        #expect(reloadedCancelled?.isArchived == true)
    }

    @Test("Partial lifecycle storage fails explicitly")
    @MainActor
    func partialLifecycleStorageFailsExplicitly() throws {
        let trialDate = Date(timeIntervalSince1970: 1_768_003_200)
        let cancelledAt = Date(timeIntervalSince1970: 1_768_089_600)
        let accessUntil = Date(timeIntervalSince1970: 1_770_768_000)
        let invalidRepresentations: [
            (
                lifecycleRawValue: String?,
                trialFirstPaidChargeAt: Date?,
                cancelledAt: Date?,
                accessUntil: Date?
            )
        ] = [
            (nil, trialDate, nil, nil),
            ("active", trialDate, nil, nil),
            ("trial", nil, nil, nil),
            ("trial", trialDate, cancelledAt, accessUntil),
            ("cancelled", nil, cancelledAt, nil),
            ("cancelled", nil, nil, accessUntil),
            ("cancelled", nil, cancelledAt, cancelledAt.addingTimeInterval(-1)),
            ("paused", nil, nil, nil),
        ]

        for (index, representation) in invalidRepresentations.enumerated() {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: SubscriptionRecord.self,
                configurations: configuration
            )
            let subscriptionID = UUID()
            container.mainContext.insert(
                SubscriptionRecord(
                    id: subscriptionID,
                    lifecycleRawValue: representation.lifecycleRawValue,
                    trialFirstPaidChargeAt:
                        representation.trialFirstPaidChargeAt,
                    cancelledAt: representation.cancelledAt,
                    accessUntil: representation.accessUntil
                )
            )
            try container.mainContext.save()
            let repository = SwiftDataSubscriptionRepository(
                modelContainer: container
            )

            #expect(
                throws: SwiftDataSubscriptionRepository.RepositoryError
                    .invalidLifecycleStorage,
                "Case \(index)"
            ) {
                try repository.subscription(id: subscriptionID)
            }
        }
    }

    @Test("A failed delete save rolls back the selected record")
    @MainActor
    func failedDeleteSaveRollsBackSelectedRecord() throws {
        let subscription = makeSubscription(
            id: UUID(uuidString: "60000000-0000-0000-0000-000000000006")!
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).createSubscription(subscription)
        let repository = SwiftDataSubscriptionRepository(
            modelContainer: container,
            save: { _ in throw SaveFailure.unavailable }
        )

        #expect(throws: SaveFailure.self) {
            try repository.deleteSubscription(id: subscription.id)
        }

        let reloaded = try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).subscription(id: subscription.id)
        #expect(reloaded == subscription)
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

    @Test("Migration aligns an inferred anchor with the confirmed renewal time")
    @MainActor
    func migrationKeepsFirstRenewalWhenLegacyTimestampsDiffer() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startDate = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2025,
                    month: 1,
                    day: 31,
                    hour: 12,
                    nanosecond: 100_000_000
                )
            )
        )
        let nextRenewal = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2025,
                    month: 2,
                    day: 28,
                    hour: 12,
                    nanosecond: 900_000_000
                )
            )
        )
        let horizon = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2025,
                    month: 2,
                    day: 28,
                    hour: 23
                )
            )
        )
        let subscriptionID = UUID(
            uuidString: "C9F06BF2-BE52-4806-A65E-D50205EA16C6"
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
        let workspace = SubscriptionWorkspace(
            repository: repository,
            now: {
                calendar.date(
                    from: DateComponents(
                        year: 2025,
                        month: 2,
                        day: 1,
                        hour: 12
                    )
                )!
            },
            calendar: calendar
        )

        workspace.loadExpectedCharges(
            subscriptionID: subscriptionID,
            through: horizon
        )

        let charges = try #require(workspace.expectedCharges)
        #expect(charges.first?.scheduledDate == nextRenewal)
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

        #expect(secondLaunch.workspace.libraryState == .empty(.current))
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

        guard case .loaded(.current, let subscriptions) =
            relaunchedApp.workspace.libraryState
        else {
            Issue.record("Expected the saved subscription after relaunch")
            return
        }
        #expect(subscriptions.map(\.serviceName) == ["Example"])
    }

    private func makeSubscription(
        id: UUID,
        lifecycle: SubscriptionLifecycle = .active,
        isArchived: Bool = false
    ) -> Subscription {
        Subscription(
            id: id,
            serviceIdentity: ServiceIdentity(
                rawValue: "manual:\(id.uuidString)"
            ),
            serviceName: "Example",
            plan: "Monthly",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: Date(
                timeIntervalSince1970: 1_769_904_000
            ),
            managementURL: nil,
            notes: "",
            lifecycle: lifecycle,
            isArchived: isArchived
        )
    }
}

private enum PreTB04Schema {
    @Model
    final class SubscriptionRecord {
        var id: UUID
        var serviceIdentityRawValue: String = ""
        var serviceName: String = ""
        var plan: String = ""
        var category: String = ""
        var originalMinorUnits: Int64 = 0
        var currencyRawValue: String = "USD"
        var billingCycleRawValue: String = "monthly"
        var billingIntervalValue: Int?
        var billingIntervalUnitRawValue: String?
        var billingTimeZoneIdentifier: String?
        var startDate: Date = Date(timeIntervalSinceReferenceDate: 0)
        var renewalAnchor: Date?
        var confirmedNextRenewal: Date = Date(
            timeIntervalSinceReferenceDate: 0
        )
        var managementURLString: String?
        var notes: String?
        var confirmedChargesData: Data?

        init(
            id: UUID,
            serviceIdentityRawValue: String = "",
            serviceName: String = "",
            plan: String = "",
            category: String = "",
            originalMinorUnits: Int64 = 0,
            currencyRawValue: String = "USD",
            billingCycleRawValue: String = "monthly",
            billingIntervalValue: Int? = nil,
            billingIntervalUnitRawValue: String? = nil,
            billingTimeZoneIdentifier: String? = nil,
            startDate: Date = Date(timeIntervalSinceReferenceDate: 0),
            renewalAnchor: Date? = nil,
            confirmedNextRenewal: Date = Date(
                timeIntervalSinceReferenceDate: 0
            ),
            managementURLString: String? = nil,
            notes: String? = nil,
            confirmedChargesData: Data? = nil
        ) {
            self.id = id
            self.serviceIdentityRawValue = serviceIdentityRawValue
            self.serviceName = serviceName
            self.plan = plan
            self.category = category
            self.originalMinorUnits = originalMinorUnits
            self.currencyRawValue = currencyRawValue
            self.billingCycleRawValue = billingCycleRawValue
            self.billingIntervalValue = billingIntervalValue
            self.billingIntervalUnitRawValue = billingIntervalUnitRawValue
            self.billingTimeZoneIdentifier = billingTimeZoneIdentifier
            self.startDate = startDate
            self.renewalAnchor = renewalAnchor
            self.confirmedNextRenewal = confirmedNextRenewal
            self.managementURLString = managementURLString
            self.notes = notes
            self.confirmedChargesData = confirmedChargesData
        }
    }
}
