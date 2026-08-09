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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let pinnedAt = Date(timeIntervalSince1970: 1_770_000_000)
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
            notes: "工作文件",
            pinnedAt: pinnedAt
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        #expect(reloadedSubscription?.pinnedAt == pinnedAt)
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
        let priceChange = PriceChange(
            id: UUID(
                uuidString: "20A09F53-5E76-4B4D-A1B0-9C3644B8455F"
            )!,
            effectiveDate: Date(timeIntervalSince1970: 1_758_837_600),
            amount: Money(minorUnits: 3_499, currency: .cny)
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
            confirmedCharges: [confirmedCharge],
            priceChanges: [priceChange]
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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

    @Test("Independent repository contexts merge appended payment history")
    @MainActor
    func independentRepositoryContextsMergeAppendedPaymentHistory() throws {
        let subscriptionID = UUID(
            uuidString: "0A0A0A0A-0000-4000-8000-000000000001"
        )!
        let original = makeSubscription(id: subscriptionID)
        let chargeA = ConfirmedCharge(
            id: UUID(uuidString: "0A0A0A0A-0000-4000-8000-00000000000A")!,
            chargedDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: Money(minorUnits: 1_001, currency: .usd)
        )
        let chargeB = ConfirmedCharge(
            id: UUID(uuidString: "0A0A0A0A-0000-4000-8000-00000000000B")!,
            chargedDate: Date(timeIntervalSince1970: 1_700_086_400),
            amount: Money(minorUnits: 1_002, currency: .usd)
        )
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: configuration
        )
        let seedRepository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        try seedRepository.createSubscription(original)

        let firstContextRepository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        let secondContextRepository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        let firstSnapshot = try #require(
            try firstContextRepository.subscription(id: subscriptionID)
        )
        let secondSnapshot = try #require(
            try secondContextRepository.subscription(id: subscriptionID)
        )

        func adding(
            _ charge: ConfirmedCharge,
            to snapshot: Subscription
        ) -> Subscription {
            Subscription(
                id: snapshot.id,
                serviceIdentity: snapshot.serviceIdentity,
                serviceName: snapshot.serviceName,
                plan: snapshot.plan,
                category: snapshot.category,
                originalAmount: snapshot.originalAmount,
                billingSchedule: snapshot.billingSchedule,
                startDate: snapshot.startDate,
                confirmedNextRenewal: snapshot.confirmedNextRenewal,
                managementURL: snapshot.managementURL,
                notes: snapshot.notes,
                confirmedCharges: [charge],
                priceChanges: snapshot.priceChanges,
                lifecycle: snapshot.lifecycle,
                isArchived: snapshot.isArchived,
                pinnedAt: snapshot.pinnedAt
            )
        }

        try firstContextRepository.updateSubscription(
            adding(chargeA, to: firstSnapshot)
        )
        try secondContextRepository.updateSubscription(
            adding(chargeB, to: secondSnapshot)
        )

        let merged = try #require(
            try SwiftDataSubscriptionRepository(modelContainer: container)
                .subscription(id: subscriptionID)
        )

        #expect(merged.confirmedCharges.count == 2)
        #expect(merged.confirmedCharges.contains(chargeA))
        #expect(merged.confirmedCharges.contains(chargeB))
    }

    @Test("Independent contexts preserve confirmed charge append order")
    @MainActor
    func independentContextsPreserveConfirmedChargeAppendOrder() throws {
        let subscriptionID = UUID(
            uuidString: "0A0A0A0A-0000-4000-8000-000000000011"
        )!
        let original = makeSubscription(id: subscriptionID)
        let firstCharge = ConfirmedCharge(
            id: UUID(
                uuidString: "F0000000-0000-4000-8000-000000000001"
            )!,
            chargedDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: Money(minorUnits: 1_101, currency: .usd)
        )
        let secondCharge = ConfirmedCharge(
            id: UUID(
                uuidString: "00000000-0000-4000-8000-000000000002"
            )!,
            chargedDate: Date(timeIntervalSince1970: 1_700_086_400),
            amount: Money(minorUnits: 1_102, currency: .usd)
        )
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        try SwiftDataSubscriptionRepository(modelContainer: container)
            .createSubscription(original)

        var secondContextForSave: ModelContext?
        let secondRepository = SwiftDataSubscriptionRepository(
            modelContainer: container,
            save: { context in
                secondContextForSave = context
            }
        )
        let secondSnapshot = try #require(
            try secondRepository.subscription(id: subscriptionID)
        )
        var interleavedAppend: (() throws -> Void)?
        let firstRepository = SwiftDataSubscriptionRepository(
            modelContainer: container,
            save: { context in
                if let interleavedAppend {
                    try interleavedAppend()
                }
                try context.save()
            }
        )
        let firstSnapshot = try #require(
            try firstRepository.subscription(id: subscriptionID)
        )
        interleavedAppend = {
            try secondRepository.updateSubscription(
                replacingPaymentHistory(
                    in: secondSnapshot,
                    confirmedCharges: [secondCharge]
                )
            )
        }

        try firstRepository.updateSubscription(
            replacingPaymentHistory(
                in: firstSnapshot,
                confirmedCharges: [firstCharge]
            )
        )
        try #require(secondContextForSave).save()

        let merged = try #require(
            try SwiftDataSubscriptionRepository(modelContainer: container)
                .subscription(id: subscriptionID)
        )

        #expect(merged.confirmedCharges.map(\.id) == [
            firstCharge.id,
            secondCharge.id,
        ])
    }

    @Test("A stale price change snapshot cannot overwrite the persisted value")
    @MainActor
    func stalePriceChangeSnapshotCannotOverwritePersistedValue() throws {
        let subscriptionID = UUID(
            uuidString: "0A0A0A0A-0000-4000-8000-000000000012"
        )!
        let priceChangeID = UUID(
            uuidString: "0A0A0A0A-0000-4000-8000-000000000013"
        )!
        let originalChange = PriceChange(
            id: priceChangeID,
            effectiveDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: Money(minorUnits: 1_201, currency: .usd)
        )
        let newerChange = PriceChange(
            id: priceChangeID,
            effectiveDate: Date(timeIntervalSince1970: 1_700_086_400),
            amount: Money(minorUnits: 1_299, currency: .usd)
        )
        let original = makeSubscription(
            id: subscriptionID,
            priceChanges: [originalChange]
        )
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        try SwiftDataSubscriptionRepository(modelContainer: container)
            .createSubscription(original)

        let firstRepository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        let staleRepository = SwiftDataSubscriptionRepository(
            modelContainer: container
        )
        let firstSnapshot = try #require(
            try firstRepository.subscription(id: subscriptionID)
        )
        let staleSnapshot = try #require(
            try staleRepository.subscription(id: subscriptionID)
        )

        try firstRepository.updateSubscription(
            replacingPaymentHistory(
                in: firstSnapshot,
                priceChanges: [newerChange]
            )
        )
        try staleRepository.updateSubscription(
            replacingPaymentHistory(
                in: staleSnapshot,
                priceChanges: [originalChange]
            )
        )

        let merged = try #require(
            try SwiftDataSubscriptionRepository(modelContainer: container)
                .subscription(id: subscriptionID)
        )

        #expect(merged.priceChanges == [newerChange])
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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

    @Test("A failed portable restore rolls back subscriptions and preferences together")
    @MainActor
    func failedPortableRestoreRollsBackEveryMutation() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            configurations: configuration
        )
        let original = makeSubscription(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000007")!
        )
        let originalPreferences = UserPreferences.default
        try SwiftDataSubscriptionRepository(modelContainer: container)
            .createSubscription(original)
        try SwiftDataUserPreferencesRepository(modelContainer: container)
            .savePreferences(originalPreferences)

        let replacement = Subscription(
            id: original.id,
            serviceIdentity: original.serviceIdentity,
            serviceName: "Restored name",
            plan: original.plan,
            category: original.category,
            originalAmount: original.originalAmount,
            billingSchedule: original.billingSchedule,
            startDate: original.startDate,
            confirmedNextRenewal: original.confirmedNextRenewal,
            managementURL: original.managementURL,
            notes: original.notes
        )
        let addition = makeSubscription(
            id: UUID(uuidString: "80000000-0000-0000-0000-000000000008")!
        )
        let restoredPreferences = UserPreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths,
            hideAmountsInCalendar: true,
            setupStatus: .completed
        )
        let importer = SwiftDataPortableBackupImportRepository(
            modelContainer: container,
            save: { _ in throw SaveFailure.unavailable }
        )

        #expect(throws: SaveFailure.self) {
            try importer.apply(
                PortableBackupMerge(
                    additions: [addition],
                    replacements: [replacement],
                    preferences: restoredPreferences
                )
            )
        }

        let subscriptions = try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).listSubscriptions()
        let preferences = try SwiftDataUserPreferencesRepository(
            modelContainer: container
        ).loadPreferences()
        #expect(subscriptions == [original])
        #expect(preferences == originalPreferences)
    }

    @Test("A failed preference save rolls back canonicalization and values")
    @MainActor
    func failedPreferenceSaveRollsBackCanonicalizationAndValues() throws {
        let container = try ModelContainer(
            for: UserPreferencesRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let canonical = UserPreferencesRecord(
            id: UserPreferencesRecord.canonicalID,
            primaryCurrencyRawValue: "USD",
            calendarProjectionHorizonMonths: 12,
            hideAmountsInCalendar: false,
            menuBarModeEnabled: false,
            appearanceModeRawValue: "light",
            setupStatusRawValue: "notCompleted"
        )
        let duplicateID = UUID(
            uuidString: "81000000-0000-4000-8000-000000000001"
        )!
        let duplicate = UserPreferencesRecord(
            id: duplicateID,
            primaryCurrencyRawValue: "EUR",
            calendarProjectionHorizonMonths: 6,
            hideAmountsInCalendar: true,
            menuBarModeEnabled: true,
            appearanceModeRawValue: "dark",
            setupStatusRawValue: "completed"
        )
        container.mainContext.insert(canonical)
        container.mainContext.insert(duplicate)
        try container.mainContext.save()
        let repository = SwiftDataUserPreferencesRepository(
            modelContainer: container,
            save: { _ in throw SaveFailure.unavailable }
        )

        #expect(throws: SaveFailure.self) {
            try repository.savePreferences(
                UserPreferences(
                    primaryCurrency: .cny,
                    calendarProjectionHorizon: .sixMonths,
                    hideAmountsInCalendar: true,
                    menuBarModeEnabled: true,
                    appearanceMode: .system,
                    setupStatus: .skipped
                )
            )
        }

        let records = try ModelContext(container).fetch(
            FetchDescriptor<UserPreferencesRecord>()
        )
        #expect(records.count == 2)
        let restoredCanonical = try #require(
            records.first { $0.id == UserPreferencesRecord.canonicalID }
        )
        let restoredDuplicate = try #require(
            records.first { $0.id == duplicateID }
        )
        #expect(restoredCanonical.primaryCurrencyRawValue == "USD")
        #expect(restoredCanonical.calendarProjectionHorizonMonths == 12)
        #expect(restoredCanonical.hideAmountsInCalendar == false)
        #expect(restoredCanonical.menuBarModeEnabled == false)
        #expect(restoredCanonical.appearanceModeRawValue == "light")
        #expect(restoredCanonical.setupStatusRawValue == "notCompleted")
        #expect(restoredDuplicate.primaryCurrencyRawValue == "EUR")
        #expect(restoredDuplicate.calendarProjectionHorizonMonths == 6)
        #expect(restoredDuplicate.hideAmountsInCalendar)
        #expect(restoredDuplicate.menuBarModeEnabled)
        #expect(restoredDuplicate.appearanceModeRawValue == "dark")
        #expect(restoredDuplicate.setupStatusRawValue == "completed")
    }

    @Test("Portable restore writes payment history as independent records")
    @MainActor
    func portableRestoreWritesIndependentPaymentHistory() throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            configurations: configuration
        )
        let subscriptionID = UUID(
            uuidString: "81000000-0000-4000-8000-000000000008"
        )!
        let charge = ConfirmedCharge(
            id: UUID(uuidString: "81000000-0000-4000-8000-000000000009")!,
            chargedDate: Date(timeIntervalSince1970: 1_768_003_200),
            amount: Money(minorUnits: 1_234, currency: .usd),
            sourceScheduledChargeID: ScheduledChargeID(
                subscriptionID: subscriptionID,
                year: 2026,
                month: 8,
                day: 3
            )
        )
        let priceChange = PriceChange(
            id: UUID(uuidString: "81000000-0000-4000-8000-00000000000A")!,
            effectiveDate: Date(timeIntervalSince1970: 1_769_904_000),
            amount: Money(minorUnits: 1_499, currency: .usd)
        )
        let incoming = Subscription(
            id: subscriptionID,
            serviceIdentity: ServiceIdentity(rawValue: "manual:portable"),
            serviceName: "Portable history",
            plan: "Standard",
            category: "Other",
            originalAmount: Money(minorUnits: 999, currency: .usd),
            billingCycle: .monthly,
            startDate: Date(timeIntervalSince1970: 1_767_225_600),
            confirmedNextRenewal: Date(timeIntervalSince1970: 1_769_904_000),
            managementURL: nil,
            notes: "",
            confirmedCharges: [charge],
            priceChanges: [priceChange]
        )

        try SwiftDataPortableBackupImportRepository(
            modelContainer: container
        ).apply(
            PortableBackupMerge(
                additions: [incoming],
                replacements: [],
                preferences: nil
            )
        )

        let reloaded = try #require(
            try SwiftDataSubscriptionRepository(modelContainer: container)
                .subscription(id: subscriptionID)
        )
        #expect(reloaded.confirmedCharges == [charge])
        #expect(reloaded.priceChanges == [priceChange])
        #expect(
            try ModelContext(container).fetch(
                FetchDescriptor<ConfirmedChargeRecord>()
            ).count == 1
        )
        #expect(
            try ModelContext(container).fetch(
                FetchDescriptor<PriceChangeRecord>()
            ).count == 1
        )
    }

    @Test("Library listing migrates legacy history from its preloaded batches")
    @MainActor
    func libraryListingMigratesLegacyHistoryFromPreloadedBatches() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let subscriptionID = UUID(
            uuidString: "81500000-0000-4000-8000-000000000001"
        )!
        let charge = ConfirmedCharge(
            id: UUID(uuidString: "81500000-0000-4000-8000-000000000002")!,
            chargedDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: Money(minorUnits: 1_200, currency: .cny)
        )
        let priceChange = PriceChange(
            id: UUID(uuidString: "81500000-0000-4000-8000-000000000003")!,
            effectiveDate: Date(timeIntervalSince1970: 1_700_086_400),
            amount: Money(minorUnits: 1_300, currency: .cny)
        )
        let record = SubscriptionRecord(
            id: subscriptionID,
            confirmedChargesData: try JSONEncoder().encode([charge]),
            priceChangesData: try JSONEncoder().encode([priceChange])
        )
        container.mainContext.insert(record)
        try container.mainContext.save()

        let subscriptions = try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).listSubscriptions()

        let subscription = try #require(subscriptions.first)
        #expect(subscription.confirmedCharges == [charge])
        #expect(subscription.priceChanges == [priceChange])
        let storedRecord = try #require(
            try ModelContext(container).fetch(
                FetchDescriptor<SubscriptionRecord>()
            ).first
        )
        #expect(storedRecord.confirmedChargesData == nil)
        #expect(storedRecord.priceChangesData == nil)
    }

    @Test("Duplicate physical history rows load as one domain occurrence")
    @MainActor
    func duplicatePhysicalHistoryRowsLoadAsOneDomainOccurrence() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let subscription = makeSubscription(
            id: UUID(uuidString: "82000000-0000-4000-8000-000000000001")!
        )
        try SwiftDataSubscriptionRepository(modelContainer: container)
            .createSubscription(subscription)
        let context = ModelContext(container)
        let priceChangeID = UUID(
            uuidString: "82000000-0000-4000-8000-000000000002"
        )!
        let scheduledID = ScheduledChargeID(
            subscriptionID: subscription.id,
            year: 2026,
            month: 8,
            day: 12
        )
        context.insert(
            PriceChangeRecord(
                id: priceChangeID,
                sequence: 0,
                effectiveDate: subscription.confirmedNextRenewal,
                amountMinorUnits: 1_100,
                currencyRawValue: "USD",
                subscriptionID: subscription.id
            )
        )
        context.insert(
            PriceChangeRecord(
                id: priceChangeID,
                sequence: 1,
                effectiveDate: subscription.confirmedNextRenewal,
                amountMinorUnits: 2_200,
                currencyRawValue: "USD",
                subscriptionID: subscription.id
            )
        )
        for (index, id) in [
            UUID(uuidString: "82000000-0000-4000-8000-000000000003")!,
            UUID(uuidString: "82000000-0000-4000-8000-000000000004")!,
        ].enumerated() {
            context.insert(
                ConfirmedChargeRecord(
                    id: id,
                    sequence: index,
                    chargedDate: subscription.confirmedNextRenewal,
                    amountMinorUnits: Int64(1_300 + index),
                    currencyRawValue: "USD",
                    sourceScheduledChargeSubscriptionID:
                        scheduledID.subscriptionID,
                    sourceScheduledChargeYear: scheduledID.year,
                    sourceScheduledChargeMonth: scheduledID.month,
                    sourceScheduledChargeDay: scheduledID.day,
                    subscriptionID: subscription.id
                )
            )
        }
        try context.save()

        let loaded = try #require(
            try SwiftDataSubscriptionRepository(modelContainer: container)
                .subscription(id: subscription.id)
        )
        #expect(loaded.priceChanges.count == 1)
        #expect(loaded.priceChanges.first?.amount.minorUnits == 1_100)
        #expect(loaded.confirmedCharges.count == 1)
        #expect(
            loaded.confirmedCharges.first?.sourceScheduledChargeID
                == scheduledID
        )
    }

    @Test("A walking-skeleton record remains readable after schema expansion")
    @MainActor
    func walkingSkeletonRecordRemainsReadable() throws {
        let subscriptionID = UUID(
            uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
        )!
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
            let persisted = try #require(
                try dependencies.workspace.subscription(
                    for: subscriptionID
                )
            )
            #expect(persisted.confirmedNextRenewal == nextRenewal)
            dependencies.workspace.loadSubscription(id: subscriptionID)
            guard case .loaded(
                let subscription,
                _,
                let nextExpectedCharge
            ) =
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
            #expect(
                subscription.confirmedNextRenewal
                    == nextExpectedCharge?.scheduledDate
            )
            #expect(subscription.managementURL == managementURL)
            #expect(subscription.notes == "Preserve legacy notes")
            #expect(subscription.confirmedCharges == [charge])
            #expect(subscription.priceChanges == [])
            #expect(subscription.lifecycle == .active)
            #expect(subscription.isArchived == false)
        }
    }

    @Test("Legacy payment history migrates once into independent records")
    @MainActor
    func legacyPaymentHistoryMigratesOnceIntoIndependentRecords() throws {
        let storeRoot = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerLegacyHistory-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer {
            try? FileManager.default.removeItem(at: storeRoot)
        }
        let token = "legacy-history"
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
            uuidString: "0B0B0B0B-0000-4000-8000-000000000001"
        )!
        let sourceScheduledChargeID = ScheduledChargeID(
            subscriptionID: subscriptionID,
            year: 2026,
            month: 7,
            day: 14
        )
        let firstCharge = ConfirmedCharge(
            id: UUID(uuidString: "0B0B0B0B-0000-4000-8000-00000000000A")!,
            chargedDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: Money(minorUnits: 1_201, currency: .cny),
            sourceScheduledChargeID: sourceScheduledChargeID
        )
        let secondCharge = ConfirmedCharge(
            id: UUID(uuidString: "0B0B0B0B-0000-4000-8000-00000000000B")!,
            chargedDate: Date(timeIntervalSince1970: 1_700_086_400),
            amount: Money(minorUnits: 1_202, currency: .cny)
        )
        let firstPriceChange = PriceChange(
            id: UUID(uuidString: "0B0B0B0B-0000-4000-8000-00000000001A")!,
            effectiveDate: Date(timeIntervalSince1970: 1_700_172_800),
            amount: Money(minorUnits: 1_301, currency: .cny)
        )
        let secondPriceChange = PriceChange(
            id: UUID(uuidString: "0B0B0B0B-0000-4000-8000-00000000001B")!,
            effectiveDate: Date(timeIntervalSince1970: 1_700_259_200),
            amount: Money(minorUnits: 1_302, currency: .cny)
        )
        let expectedCharges = [firstCharge, secondCharge]
        let expectedPriceChanges = [firstPriceChange, secondPriceChange]

        do {
            let legacySchema = Schema([
                PreTB04Schema.SubscriptionRecord.self
            ])
            let legacyConfiguration = ModelConfiguration(
                "LegacyHistory",
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
                    serviceIdentityRawValue: "manual:legacy-history",
                    serviceName: "Legacy History",
                    originalMinorUnits: 1_000,
                    currencyRawValue: "CNY",
                    startDate: Date(timeIntervalSince1970: 1_699_913_600),
                    confirmedNextRenewal: Date(
                        timeIntervalSince1970: 1_702_505_600
                    ),
                    confirmedChargesData: try JSONEncoder().encode(
                        expectedCharges
                    ),
                    priceChangesData: try JSONEncoder().encode(
                        expectedPriceChanges
                    )
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
                    "Expected migrated store launch \(launchNumber) to be ready"
                )
                return
            }
            let reloaded = try #require(
                try dependencies.workspace.subscription(for: subscriptionID)
            )
            #expect(reloaded.confirmedCharges == expectedCharges)
            #expect(reloaded.priceChanges == expectedPriceChanges)

            let context = ModelContext(dependencies.modelContainer)
            #expect(
                try context.fetch(FetchDescriptor<ConfirmedChargeRecord>())
                    .count == 2
            )
            #expect(
                try context.fetch(FetchDescriptor<PriceChangeRecord>())
                    .count == 2
            )
            let legacyRecord = try #require(
                try context.fetch(FetchDescriptor<SubscriptionRecord>())
                    .first
            )
            #expect(legacyRecord.confirmedChargesData == nil)
            #expect(legacyRecord.priceChangesData == nil)
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(
            reloadedTrial?.lifecycle.status(
                asOf: trialDate.addingTimeInterval(-86_400),
                timeZone: utc
            ) == .trial
        )
        #expect(
            reloadedTrial?.lifecycle.status(
                asOf: trialDate,
                timeZone: utc
            ) == .active
        )
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
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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

    @Test("A corrupt subscription record does not hide valid library rows")
    @MainActor
    func corruptSubscriptionRecordDoesNotHideValidLibraryRows() throws {
        let validID = UUID(
            uuidString: "50000000-0000-4000-8000-000000000001"
        )!
        let corruptID = UUID(
            uuidString: "50000000-0000-4000-8000-000000000002"
        )!
        let corruptBlob = Data([0xFF, 0x00, 0x01])
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        container.mainContext.insert(SubscriptionRecord(id: validID))
        container.mainContext.insert(
            SubscriptionRecord(
                id: corruptID,
                confirmedChargesData: corruptBlob
            )
        )
        try container.mainContext.save()

        let subscriptions = try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).listSubscriptions()

        #expect(subscriptions.map(\.id) == [validID])
        #expect(!subscriptions.isEmpty)

        let records = try container.mainContext.fetch(
            FetchDescriptor<SubscriptionRecord>()
        )
        #expect(records.count == 2)
        #expect(
            records.first(where: { $0.id == corruptID })?
                .confirmedChargesData == corruptBlob
        )
    }

    @Test("Mixed legacy blob corruption preserves the corrupt record")
    @MainActor
    func mixedLegacyBlobCorruptionPreservesCorruptRecord() throws {
        let validID = UUID(
            uuidString: "50000000-0000-4000-8000-000000000011"
        )!
        let corruptID = UUID(
            uuidString: "50000000-0000-4000-8000-000000000012"
        )!
        let legacyCharge = ConfirmedCharge(
            id: UUID(
                uuidString: "50000000-0000-4000-8000-000000000013"
            )!,
            chargedDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: Money(minorUnits: 1_301, currency: .usd)
        )
        let confirmedChargesData = try JSONEncoder().encode([legacyCharge])
        let corruptPriceChangesData = Data([0xFF, 0x00, 0x01])
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        container.mainContext.insert(SubscriptionRecord(id: validID))
        container.mainContext.insert(
            SubscriptionRecord(
                id: corruptID,
                confirmedChargesData: confirmedChargesData,
                priceChangesData: corruptPriceChangesData
            )
        )
        try container.mainContext.save()

        let subscriptions = try SwiftDataSubscriptionRepository(
            modelContainer: container
        ).listSubscriptions()

        #expect(subscriptions.map(\.id) == [validID])
        let context = ModelContext(container)
        let corruptRecord = try #require(
            try context.fetch(FetchDescriptor<SubscriptionRecord>())
                .first(where: { $0.id == corruptID })
        )
        #expect(corruptRecord.confirmedChargesData == confirmedChargesData)
        #expect(
            corruptRecord.priceChangesData == corruptPriceChangesData
        )
        #expect(
            try context.fetch(FetchDescriptor<ConfirmedChargeRecord>())
                .filter { $0.subscription?.id == corruptID }
                .isEmpty
        )
        #expect(
            try context.fetch(FetchDescriptor<PriceChangeRecord>())
                .filter { $0.subscription?.id == corruptID }
                .isEmpty
        )
    }

    @Test("A failed delete save rolls back the selected record")
    @MainActor
    func failedDeleteSaveRollsBackSelectedRecord() throws {
        let subscription = makeSubscription(
            id: UUID(uuidString: "60000000-0000-0000-0000-000000000006")!
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        isArchived: Bool = false,
        priceChanges: [PriceChange] = []
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
            priceChanges: priceChanges,
            lifecycle: lifecycle,
            isArchived: isArchived
        )
    }

    private func replacingPaymentHistory(
        in snapshot: Subscription,
        confirmedCharges: [ConfirmedCharge]? = nil,
        priceChanges: [PriceChange]? = nil
    ) -> Subscription {
        Subscription(
            id: snapshot.id,
            serviceIdentity: snapshot.serviceIdentity,
            serviceName: snapshot.serviceName,
            plan: snapshot.plan,
            category: snapshot.category,
            originalAmount: snapshot.originalAmount,
            billingSchedule: snapshot.billingSchedule,
            startDate: snapshot.startDate,
            confirmedNextRenewal: snapshot.confirmedNextRenewal,
            managementURL: snapshot.managementURL,
            notes: snapshot.notes,
            confirmedCharges: confirmedCharges ?? snapshot.confirmedCharges,
            priceChanges: priceChanges ?? snapshot.priceChanges,
            lifecycle: snapshot.lifecycle,
            isArchived: snapshot.isArchived,
            pinnedAt: snapshot.pinnedAt
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
        var priceChangesData: Data?

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
            confirmedChargesData: Data? = nil,
            priceChangesData: Data? = nil
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
            self.priceChangesData = priceChangesData
        }
    }
}
