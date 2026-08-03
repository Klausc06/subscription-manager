import CloudKit
import Foundation
import SwiftData
import SubscriptionCore
import Testing
@testable import SubscriptionManager

private enum Task4LegacySchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [UserPreferencesRecord.self]
    }

    @Model
    final class UserPreferencesRecord {
        var primaryCurrencyRawValue: String = "CNY"
        var calendarProjectionHorizonMonths: Int = 12
        var hideAmountsInCalendar: Bool = false
        var menuBarModeEnabled: Bool = false
        var setupStatusRawValue: String = "notCompleted"

        init(
            primaryCurrencyRawValue: String = "CNY",
            calendarProjectionHorizonMonths: Int = 12,
            hideAmountsInCalendar: Bool = false,
            menuBarModeEnabled: Bool = false,
            setupStatusRawValue: String = "notCompleted"
        ) {
            self.primaryCurrencyRawValue = primaryCurrencyRawValue
            self.calendarProjectionHorizonMonths =
                calendarProjectionHorizonMonths
            self.hideAmountsInCalendar = hideAmountsInCalendar
            self.menuBarModeEnabled = menuBarModeEnabled
            self.setupStatusRawValue = setupStatusRawValue
        }
    }
}

private enum Task4CurrentSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SubscriptionManager.UserPreferencesRecord.self]
    }
}

private enum Task4MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [Task4LegacySchema.self, Task4CurrentSchema.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: Task4LegacySchema.self,
                toVersion: Task4CurrentSchema.self
            ),
        ]
    }
}

struct AppDependenciesTests {
    @Test("Production SwiftData schema is compatible with CloudKit")
    @MainActor
    func productionSchemaSupportsCloudKit() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerCloudKitSchemaTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let schema = Schema([
            SubscriptionRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self,
        ])
        let configuration = ModelConfiguration(
            "CloudKitCompatibility",
            schema: schema,
            url: directory.appending(path: "CloudKitCompatibility.store"),
            cloudKitDatabase: .private(AppDependencies.cloudKitContainerID)
        )

        _ = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    @Test("Only production storage selects the private CloudKit container")
    @MainActor
    func cloudKitSelectionKeepsUITestingOffline() {
        #expect(
            AppDependencies.cloudKitSelection(for: .production)
                == .privateContainer(AppDependencies.cloudKitContainerID)
        )
        #expect(
            AppDependencies.cloudKitSelection(
                for: .production,
                hasCloudKitEntitlement: false
            ) == .disabled
        )
        #expect(
            AppDependencies.cloudKitSelection(for: .ephemeralUITesting)
                == .disabled
        )
        #expect(
            AppDependencies.cloudKitSelection(
                for: .namedUITesting(token: "fixture")
            ) == .disabled
        )
    }

    @Test("CloudKit account states map to user-visible library sync states")
    @MainActor
    func cloudKitAccountStatusMapsToSyncStatus() async {
        let signedOut = CloudKitLibrarySyncMonitor(
            accountStatus: { .noAccount }
        )
        let available = CloudKitLibrarySyncMonitor(
            accountStatus: { .available }
        )

        #expect(await signedOut.refreshStatus() == .signedOut)
        #expect(await available.refreshStatus() == .current)
    }

    @Test("A named UI testing store is ignored outside UI testing")
    @MainActor
    func namedStoreRequiresUITestingMode() throws {
        let selection = try AppDependencies.storeSelection(
            arguments: [
                "SubscriptionManager",
                "--ui-testing-store",
                "must-not-select-a-test-store",
            ]
        )

        #expect(selection == .production)
    }

    @Test("UI testing can select a named persistent store")
    @MainActor
    func namedStoreIsAvailableInUITestingMode() throws {
        let selection = try AppDependencies.storeSelection(
            arguments: [
                "SubscriptionManager",
                "--ui-testing",
                "--ui-testing-store",
                "relaunch-contract",
            ]
        )

        #expect(selection == .namedUITesting(token: "relaunch-contract"))
    }

    @Test("Preferences survive a SwiftData repository reload")
    @MainActor
    func preferencesRoundTripThroughSwiftData() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let expected = UserPreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths,
            hideAmountsInCalendar: true,
            menuBarModeEnabled: true,
            appearanceMode: .dark,
            setupStatus: .completed
        )

        try SwiftDataUserPreferencesRepository(modelContainer: container)
            .savePreferences(expected)

        let reloaded = try SwiftDataUserPreferencesRepository(
            modelContainer: container
        ).loadPreferences()

        #expect(reloaded == expected)
    }

    @Test("All appearance modes survive repository rebuilds")
    @MainActor
    func appearanceModesRoundTrip() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let repository = SwiftDataUserPreferencesRepository(
            modelContainer: container
        )

        for appearanceMode in AppearanceMode.allCases {
            let expected = UserPreferences(
                primaryCurrency: .usd,
                calendarProjectionHorizon: .twelveMonths,
                appearanceMode: appearanceMode,
                setupStatus: .completed
            )
            try repository.savePreferences(expected)
            let reloaded = try SwiftDataUserPreferencesRepository(
                modelContainer: container
            ).loadPreferences()
            #expect(reloaded == expected)
        }

    }

    @Test("Reopening a real pre-appearance store defaults the missing field to system")
    @MainActor
    func reopeningLegacyStoreDefaultsMissingAppearanceToSystem() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerTask4LegacyStore-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storeURL = directory.appending(path: "SubscriptionManager.store")

        do {
            let legacySchema = Schema(versionedSchema: Task4LegacySchema.self)
            let legacyConfiguration = ModelConfiguration(
                "Task4Legacy",
                schema: legacySchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [legacyConfiguration]
            )
            let context = ModelContext(legacyContainer)
            context.insert(
                Task4LegacySchema.UserPreferencesRecord(
                    primaryCurrencyRawValue: "EUR",
                    calendarProjectionHorizonMonths: 6,
                    setupStatusRawValue: "completed"
                )
            )
            try context.save()
        }

        let currentSchema = Schema(versionedSchema: Task4CurrentSchema.self)
        let currentConfiguration = ModelConfiguration(
            "Task4Current",
            schema: currentSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let reopenedContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: Task4MigrationPlan.self,
            configurations: [currentConfiguration]
        )

        let migratedPreferences = try SwiftDataUserPreferencesRepository(
            modelContainer: reopenedContainer
        ).loadPreferences()
        #expect(migratedPreferences?.primaryCurrency == .eur)
        #expect(migratedPreferences?.calendarProjectionHorizon == .sixMonths)
        #expect(migratedPreferences?.setupStatus == .completed)
        #expect(migratedPreferences?.appearanceMode == .system)
    }

    @Test("Calendar projection mappings survive a SwiftData repository reload")
    @MainActor
    func calendarProjectionMappingsRoundTripThroughSwiftData() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let repository = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: container
        )

        try repository.saveCalendarIdentifier("calendar-1")
        try repository.saveEventIdentifier(
            "event-1",
            for: "renewal-1",
            calendarIdentifier: "calendar-1"
        )
        try repository.saveCalendarIdentifier("calendar-2")

        let reloaded = SwiftDataCalendarProjectionMappingRepository(
            modelContainer: container
        )

        #expect(try reloaded.calendarIdentifier() == "calendar-2")
        #expect(try reloaded.eventIdentifier(for: "renewal-1") == "event-1")
    }

    @Test("Exchange-rate cache preserves snapshots and refresh attempts")
    @MainActor
    func exchangeRateCacheRoundTripsState() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SubscriptionManagerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_769_356_800)
        let expected = ExchangeRateCacheState(
            snapshot: ExchangeRateSnapshot(
                base: .eur,
                providerDate: now,
                fetchedAt: now,
                source: "fixture",
                rates: [.eur: 1, .usd: 1.2, .cny: 8.4]
            ),
            lastAttemptAt: now
        )
        let cache = FileExchangeRateCache(directory: directory)

        try cache.saveState(expected)

        #expect(try cache.loadState() == expected)
    }

    @Test("Frankfurter v2 rates decode only complete requested quotes")
    @MainActor
    func frankfurterRatesDecodeIntoSnapshot() throws {
        let data = Data("""
        [
          {"date":"2026-07-29","base":"EUR","quote":"CNY","rate":8.4},
          {"date":"2026-07-29","base":"EUR","quote":"USD","rate":1.2}
        ]
        """.utf8)
        let fetchedAt = Date(timeIntervalSince1970: 1_769_356_800)

        let snapshot = try FrankfurterExchangeRateSource.decodeSnapshot(
            data: data,
            base: .eur,
            quotes: [.cny, .usd],
            fetchedAt: fetchedAt
        )

        #expect(snapshot.base == .eur)
        #expect(snapshot.rates == [.eur: 1, .cny: 8.4, .usd: 1.2])
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.source == "Frankfurter v2")
    }
}
