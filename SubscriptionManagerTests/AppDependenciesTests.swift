import CloudKit
import Foundation
import SwiftData
import SubscriptionCore
import Testing
@testable import SubscriptionManager

struct AppDependenciesTests {
    @Test("Only production storage selects the private CloudKit container")
    @MainActor
    func cloudKitSelectionKeepsUITestingOffline() {
        #expect(
            AppDependencies.cloudKitSelection(for: .production)
                == .privateContainer(AppDependencies.cloudKitContainerID)
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
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let expected = UserPreferences(
            primaryCurrency: .usd,
            calendarProjectionHorizon: .sixMonths,
            hideAmountsInCalendar: true,
            setupStatus: .completed
        )

        try SwiftDataUserPreferencesRepository(modelContainer: container)
            .savePreferences(expected)

        let reloaded = try SwiftDataUserPreferencesRepository(
            modelContainer: container
        ).loadPreferences()

        #expect(reloaded == expected)
    }

    @Test("Calendar projection mappings survive a SwiftData repository reload")
    @MainActor
    func calendarProjectionMappingsRoundTripThroughSwiftData() throws {
        let container = try ModelContainer(
            for: SubscriptionRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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
