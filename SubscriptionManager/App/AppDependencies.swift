import Foundation
import SwiftData
import SubscriptionCore

@MainActor
struct AppDependencies {
    enum CloudKitSelection: Equatable {
        case privateContainer(String)
        case disabled
    }

    static let cloudKitContainerID = "iCloud.com.klausc06.SubscriptionManager"

    let modelContainer: ModelContainer
    let workspace: SubscriptionWorkspace

    static func cloudKitSelection(
        for selection: AppStoreSelection,
        hasCloudKitEntitlement: Bool = true
    ) -> CloudKitSelection {
        switch selection {
        case .production where hasCloudKitEntitlement:
            .privateContainer(cloudKitContainerID)
        case .production, .ephemeralUITesting, .namedUITesting:
            .disabled
        }
    }

    static func cloudKitDatabase(
        for selection: AppStoreSelection,
        hasCloudKitEntitlement: Bool = true
    ) -> ModelConfiguration.CloudKitDatabase {
        switch cloudKitSelection(
            for: selection,
            hasCloudKitEntitlement: hasCloudKitEntitlement
        ) {
        case .privateContainer(let containerID):
            .private(containerID)
        case .disabled:
            .none
        }
    }

    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        storeDirectory: URL? = nil,
        isRunningTests: Bool = ProcessInfo.processInfo.environment[
            "XCTestConfigurationFilePath"
        ] != nil,
        hasCloudKitEntitlement: Bool =
            AppRuntimeEntitlements.hasCloudKitContainer,
        hasAppGroupEntitlement: Bool =
            AppRuntimeEntitlements.hasAppGroup
    ) -> AppStartupState {
        let schema = Schema([
            SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self
        ])
        let cloudSchema = Schema([
            SubscriptionRecord.self,
            ConfirmedChargeRecord.self,
            PriceChangeRecord.self,
            UserPreferencesRecord.self
        ])
        let localMappingSchema = Schema([
            CalendarProjectionMappingRecord.self
        ])
        let effectiveArguments = (isRunningTests
            && !arguments.contains("--ui-testing"))
            ? arguments + ["--ui-testing"]
            : arguments
        let selection: AppStoreSelection
        do {
            selection = try storeSelection(arguments: effectiveArguments)
        } catch {
            return .failed(AppStartupFailure(underlyingError: error))
        }
        #if DEBUG
        let failsLifecycleMutations = effectiveArguments.contains("--ui-testing")
            && effectiveArguments.contains("--ui-testing-fail-lifecycle-mutations")
        #else
        let failsLifecycleMutations = false
        #endif
        let seedsLegacyChatGPTPlus =
            effectiveArguments.contains("--ui-testing")
            && effectiveArguments.contains(
                "--ui-testing-seed-legacy-chatgpt-plus"
            )
        let seedsTask6OccurrenceFixture =
            effectiveArguments.contains("--ui-testing")
            && effectiveArguments.contains(
                "--ui-testing-seed-task6-occurrence-fixture"
            )

        return make(
            failsLifecycleMutations: failsLifecycleMutations,
            seedsLegacyChatGPTPlus: seedsLegacyChatGPTPlus,
            seedsTask6OccurrenceFixture: seedsTask6OccurrenceFixture,
            allowsExchangeRateNetworking: !effectiveArguments.contains("--ui-testing"),
            allowsCalendarImport: selection == .production,
            widgetSnapshotPublisher: selection == .production
                && hasAppGroupEntitlement
                ? AppGroupWidgetSnapshotPublisher()
                : nil,
            syncMonitor: selection == .production
                && hasCloudKitEntitlement
                ? CloudKitLibrarySyncMonitor()
                : nil
        ) {
            let cloudConfiguration: ModelConfiguration
            let localMappingConfiguration: ModelConfiguration
            let legacyStoreURL: URL?
            switch selection {
            case .namedUITesting(let token):
                let rootDirectory: URL
                if let storeDirectory {
                    rootDirectory = storeDirectory
                } else {
                    rootDirectory = try FileManager.default.url(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                }
                let directory = rootDirectory.appending(
                    path: "SubscriptionManagerUITests",
                    directoryHint: .isDirectory
                )
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                cloudConfiguration = ModelConfiguration(
                    "UITesting-\(token)",
                    schema: cloudSchema,
                    url: directory.appending(path: "\(token).store"),
                    allowsSave: true,
                    cloudKitDatabase: cloudKitDatabase(
                        for: .namedUITesting(token: token)
                    )
                )
                legacyStoreURL = directory.appending(path: "\(token).store")
                localMappingConfiguration = ModelConfiguration(
                    "UITesting-\(token)-CalendarMappings",
                    schema: localMappingSchema,
                    url: directory.appending(
                        path: "\(token).calendar-mappings.store"
                    ),
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            case .ephemeralUITesting:
                legacyStoreURL = nil
                cloudConfiguration = ModelConfiguration(
                    "EphemeralCloudLibrary",
                    schema: cloudSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: cloudKitDatabase(
                        for: .ephemeralUITesting,
                        hasCloudKitEntitlement: hasCloudKitEntitlement
                    )
                )
                localMappingConfiguration = ModelConfiguration(
                    "EphemeralCalendarMappings",
                    schema: localMappingSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            case .production:
                cloudConfiguration = ModelConfiguration(
                    schema: cloudSchema,
                    cloudKitDatabase: cloudKitDatabase(
                        for: .production,
                        hasCloudKitEntitlement: hasCloudKitEntitlement
                    )
                )
                legacyStoreURL = cloudConfiguration.url
                let applicationSupportDirectory = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                ).appending(
                    path: "SubscriptionManager",
                    directoryHint: .isDirectory
                )
                try FileManager.default.createDirectory(
                    at: applicationSupportDirectory,
                    withIntermediateDirectories: true
                )
                localMappingConfiguration = ModelConfiguration(
                    "CalendarProjectionMappings",
                    schema: localMappingSchema,
                    url: applicationSupportDirectory.appending(
                        path: "CalendarProjectionMappings.store"
                    ),
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            }
            if let legacyStoreURL {
                try migrateLegacyCalendarProjectionMappings(
                    legacySchema: schema,
                    legacyStoreURL: legacyStoreURL,
                    localMappingSchema: localMappingSchema,
                    localMappingConfiguration: localMappingConfiguration
                )
            }
            return try ModelContainer(
                for: schema,
                configurations: [
                    cloudConfiguration,
                    localMappingConfiguration,
                ]
            )
        }
    }

    private struct LegacyCalendarProjectionMapping {
        let projectionUID: String
        let eventIdentifier: String
        let calendarIdentifier: String
        let calendarSyncDisabled: Bool
    }

    private static func migrateLegacyCalendarProjectionMappings(
        legacySchema: Schema,
        legacyStoreURL: URL,
        localMappingSchema: Schema,
        localMappingConfiguration: ModelConfiguration
    ) throws {
        guard FileManager.default.fileExists(atPath: legacyStoreURL.path) else {
            return
        }

        let legacyConfiguration = ModelConfiguration(
            "LegacyCalendarProjectionMappings",
            schema: legacySchema,
            url: legacyStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let legacyContainer = try ModelContainer(
            for: legacySchema,
            configurations: [legacyConfiguration]
        )
        let legacyContext = ModelContext(legacyContainer)
        let legacyMappings = try legacyContext.fetch(
            FetchDescriptor<CalendarProjectionMappingRecord>()
        ).map {
            LegacyCalendarProjectionMapping(
                projectionUID: $0.projectionUID,
                eventIdentifier: $0.eventIdentifier,
                calendarIdentifier: $0.calendarIdentifier,
                calendarSyncDisabled: $0.calendarSyncDisabled
            )
        }
        guard !legacyMappings.isEmpty else { return }

        let localContainer = try ModelContainer(
            for: localMappingSchema,
            configurations: [localMappingConfiguration]
        )
        let localContext = ModelContext(localContainer)
        let localMappings = try localContext.fetch(
            FetchDescriptor<CalendarProjectionMappingRecord>()
        )
        var localProjectionUIDs = Set(
            localMappings.lazy
                .map(\.projectionUID)
                .filter { !$0.isEmpty }
        )
        var hasLocalMetadata = localMappings.contains {
            $0.projectionUID.isEmpty
        }

        for mapping in legacyMappings {
            if mapping.projectionUID.isEmpty {
                guard !hasLocalMetadata else { continue }
                hasLocalMetadata = true
            } else {
                guard localProjectionUIDs.insert(mapping.projectionUID).inserted
                else { continue }
            }
            let migrated = CalendarProjectionMappingRecord(
                projectionUID: mapping.projectionUID,
                eventIdentifier: mapping.eventIdentifier,
                calendarIdentifier: mapping.calendarIdentifier
            )
            migrated.calendarSyncDisabled = mapping.calendarSyncDisabled
            localContext.insert(migrated)
        }
        if localContext.hasChanges {
            try localContext.save()
        }
    }

    static func make(
        failsLifecycleMutations: Bool = false,
        seedsLegacyChatGPTPlus: Bool = false,
        seedsTask6OccurrenceFixture: Bool = false,
        allowsExchangeRateNetworking: Bool = true,
        allowsCalendarImport: Bool = false,
        widgetSnapshotPublisher: (any WidgetSnapshotPublishing)? = nil,
        syncMonitor: (any LibrarySyncMonitor)? = nil,
        modelContainer: () throws -> ModelContainer
    ) -> AppStartupState {
        do {
            let modelContainer = try modelContainer()
            let repository = SwiftDataSubscriptionRepository(
                modelContainer: modelContainer
            )
            let preferencesRepository = SwiftDataUserPreferencesRepository(
                modelContainer: modelContainer
            )
            if seedsLegacyChatGPTPlus {
                try seedLegacyChatGPTPlusSubscription(
                    repository: repository,
                    preferencesRepository: preferencesRepository
                )
            }
            if seedsTask6OccurrenceFixture {
                try seedTask6OccurrenceFixture(
                    repository: repository,
                    preferencesRepository: preferencesRepository
                )
            }
            let portableBackupImportRepository =
                SwiftDataPortableBackupImportRepository(
                    modelContainer: modelContainer
                )
            let calendarProjectionImporter: any CalendarProjectionImporter
            let calendarProjectionReconciler:
                (any CalendarProjectionReconciler)?
            if allowsCalendarImport {
                let adapter = EventKitCalendarProjectionImporter(
                    modelContainer: modelContainer
                )
                calendarProjectionImporter = adapter
                calendarProjectionReconciler = adapter
            } else {
                calendarProjectionImporter = UnavailableCalendarProjectionImporter()
                calendarProjectionReconciler = nil
            }
            let workspaceRepository: any SubscriptionRepository
            #if DEBUG
            workspaceRepository = failsLifecycleMutations
                ? FailingLifecycleMutationRepository(base: repository)
                : repository
            #else
            workspaceRepository = repository
            #endif
            let applicationSupportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "SubscriptionManager", directoryHint: .isDirectory)
            let catalogDirectory = applicationSupportDirectory.appending(
                path: "Catalog",
                directoryHint: .isDirectory
            )
            let exchangeRateDirectory = applicationSupportDirectory.appending(
                path: "Insights",
                directoryHint: .isDirectory
            )
            let catalogCache = FileCatalogCache(directory: catalogDirectory)
            let exchangeRateCache = FileExchangeRateCache(
                directory: exchangeRateDirectory
            )
            let bundledCatalog = BundledCatalogRepository()
            let catalogRepository = CachedCatalogRepository(
                bundled: bundledCatalog,
                cache: catalogCache
            )
            let workspace = SubscriptionWorkspace(
                repository: workspaceRepository,
                preferencesRepository: preferencesRepository,
                portableBackupImportRepository:
                    portableBackupImportRepository,
                widgetSnapshotPublisher: widgetSnapshotPublisher,
                catalogRepository: catalogRepository,
                catalogUpdateSource: GitHubCatalogUpdateSource(),
                catalogCache: catalogCache,
                exchangeRateSource: allowsExchangeRateNetworking
                    ? FrankfurterExchangeRateSource()
                    : nil,
                exchangeRateCache: allowsExchangeRateNetworking
                    ? exchangeRateCache
                    : nil,
                syncMonitor: syncMonitor,
                calendarProjectionImporter: calendarProjectionImporter,
                calendarProjectionReconciler: calendarProjectionReconciler
            )
            if let syncMonitor = syncMonitor as?
                CloudKitLibrarySyncMonitor
            {
                syncMonitor.setWorkspaceReloadHandler { [weak workspace] in
                    await MainActor.run {
                        workspace?.reloadLibrary()
                    }
                }
            }
            return .ready(
                AppDependencies(
                    modelContainer: modelContainer,
                    workspace: workspace
                )
            )
        } catch {
            return .failed(AppStartupFailure(underlyingError: error))
        }
    }

    private static func seedLegacyChatGPTPlusSubscription(
        repository: SwiftDataSubscriptionRepository,
        preferencesRepository: SwiftDataUserPreferencesRepository
    ) throws {
        let legacyIdentity = ServiceIdentity(
            rawValue: "catalog:chatgpt-plus"
        )
        let seedID = UUID(
            uuidString: "C0DEC0DE-0000-4000-8000-000000000023"
        )!
        if try !repository.listSubscriptions().contains(where: {
            $0.id == seedID || $0.serviceIdentity == legacyIdentity
        }) {
            let start = Date(timeIntervalSince1970: 1_767_225_600)
            let calendar = BillingCalendar.calendar(
                timeZone: TimeZone(identifier: "UTC")!
            )
            let nextRenewal = calendar.date(
                byAdding: .month,
                value: 1,
                to: start
            ) ?? start
            try repository.createSubscription(
                Subscription(
                    id: seedID,
                    serviceIdentity: legacyIdentity,
                    serviceName: "ChatGPT Plus",
                    plan: "Plus",
                    category: "Productivity",
                    originalAmount: Money(
                        minorUnits: 2_000,
                        currency: .usd
                    ),
                    billingSchedule: FixedBillingSchedule(
                        interval: .monthly,
                        renewalAnchor: start,
                        timeZoneIdentifier: "UTC"
                    ),
                    startDate: start,
                    confirmedNextRenewal: nextRenewal,
                    managementURL: URL(string: "https://chatgpt.com/"),
                    notes: ""
                )
            )
        }
        try preferencesRepository.savePreferences(.default)
    }

    private static func seedTask6OccurrenceFixture(
        repository: SwiftDataSubscriptionRepository,
        preferencesRepository: SwiftDataUserPreferencesRepository
    ) throws {
        let now = Date()
        let fixtureTimeZone = TimeZone(identifier: "UTC")!
        var calendar = BillingCalendar.calendar(timeZone: fixtureTimeZone)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let today = calendar.startOfDay(for: now)

        func date(
            monthsFromToday: Int,
            hour: Int = 12
        ) -> Date {
            let shifted = calendar.date(
                byAdding: .month,
                value: monthsFromToday,
                to: today
            ) ?? today
            return calendar.date(
                bySettingHour: hour,
                minute: 0,
                second: 0,
                of: shifted
            ) ?? shifted
        }

        func scheduledID(
            subscriptionID: UUID,
            scheduledDate: Date
        ) -> ScheduledChargeID {
            let components = calendar.dateComponents(
                [.year, .month, .day],
                from: scheduledDate
            )
            return ScheduledChargeID(
                subscriptionID: subscriptionID,
                year: components.year!,
                month: components.month!,
                day: components.day!
            )
        }

        func fixtureSubscription(
            id: UUID,
            serviceName: String,
            interval: BillingInterval,
            anchor: Date,
            startDate: Date,
            confirmedCharges: [ConfirmedCharge] = []
        ) -> Subscription {
            Subscription(
                id: id,
                serviceIdentity: ServiceIdentity(
                    rawValue: "manual:\(id.uuidString.lowercased())"
                ),
                serviceName: serviceName,
                plan: "Fixture Plan",
                category: "Testing",
                originalAmount: Money(
                    minorUnits: 3_000,
                    currency: .usd
                ),
                billingSchedule: FixedBillingSchedule(
                    interval: interval,
                    renewalAnchor: anchor,
                    timeZoneIdentifier: fixtureTimeZone.identifier
                ),
                startDate: startDate,
                confirmedNextRenewal: anchor,
                managementURL: nil,
                notes: "",
                confirmedCharges: confirmedCharges
            )
        }

        let directID = UUID(
            uuidString: "C0DEC0DE-0000-4000-8000-000000000061"
        )!
        let archivedID = UUID(
            uuidString: "C0DEC0DE-0000-4000-8000-000000000062"
        )!
        let dueTodayID = UUID(
            uuidString: "C0DEC0DE-0000-4000-8000-000000000063"
        )!
        let overdueID = UUID(
            uuidString: "C0DEC0DE-0000-4000-8000-000000000064"
        )!
        let futureID = UUID(
            uuidString: "C0DEC0DE-0000-4000-8000-000000000065"
        )!
        let confirmedID = UUID(
            uuidString: "C0DEC0DE-0000-4000-8000-000000000066"
        )!

        let dueToday = date(monthsFromToday: 0)
        let overdue = date(monthsFromToday: -2)
        let future = date(monthsFromToday: 1)
        let confirmedOccurrence = date(monthsFromToday: 0)
        let fixtures = [
            fixtureSubscription(
                id: directID,
                serviceName: "Direct Editor Fixture",
                interval: .monthly,
                anchor: date(monthsFromToday: 1),
                startDate: date(monthsFromToday: -1)
            ),
            fixtureSubscription(
                id: archivedID,
                serviceName: "Archived Editor Fixture",
                interval: .monthly,
                anchor: date(monthsFromToday: 1),
                startDate: date(monthsFromToday: -1)
            ),
            fixtureSubscription(
                id: dueTodayID,
                serviceName: "Due Today Fixture",
                interval: .quarterly,
                anchor: dueToday,
                startDate: dueToday
            ),
            fixtureSubscription(
                id: overdueID,
                serviceName: "Overdue Quarterly Fixture",
                interval: .quarterly,
                anchor: overdue,
                startDate: overdue
            ),
            fixtureSubscription(
                id: futureID,
                serviceName: "Future Quarterly Fixture",
                interval: .quarterly,
                anchor: future,
                startDate: future
            ),
            fixtureSubscription(
                id: confirmedID,
                serviceName: "Confirmed Quarterly Fixture",
                interval: .quarterly,
                anchor: confirmedOccurrence,
                startDate: confirmedOccurrence,
                confirmedCharges: [
                    ConfirmedCharge(
                        id: UUID(
                            uuidString:
                                "C0DEC0DE-0000-4000-8000-000000000067"
                        )!,
                        chargedDate: now,
                        amount: Money(
                            minorUnits: 3_000,
                            currency: .usd
                        ),
                        sourceScheduledChargeID: scheduledID(
                            subscriptionID: confirmedID,
                            scheduledDate: confirmedOccurrence
                        )
                    )
                ]
            ),
        ]
        let existingIDs = Set(
            try repository.listSubscriptions().map(\.id)
        )
        for fixture in fixtures where !existingIDs.contains(fixture.id) {
            try repository.createSubscription(fixture)
        }
        try preferencesRepository.savePreferences(.default)
    }

    static func storeSelection(
        arguments: [String]
    ) throws -> AppStoreSelection {
        guard arguments.contains("--ui-testing") else {
            return .production
        }
        if let token = try namedUITestingStoreToken(in: arguments) {
            return .namedUITesting(token: token)
        }
        return .ephemeralUITesting
    }

    private static func namedUITestingStoreToken(
        in arguments: [String]
    ) throws -> String? {
        guard let argumentIndex = arguments.firstIndex(
            of: "--ui-testing-store"
        ) else {
            return nil
        }
        let valueIndex = arguments.index(after: argumentIndex)
        guard arguments.indices.contains(valueIndex) else {
            throw UITestingStoreError.missingToken
        }
        let token = arguments[valueIndex]
        let allowedCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        guard !token.isEmpty,
              token.unicodeScalars.allSatisfy(allowedCharacters.contains)
        else {
            throw UITestingStoreError.invalidToken
        }
        return token
    }
}

enum AppRuntimeEntitlements {
    static let hasAppGroup = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier:
            WidgetSnapshotStore.appGroupIdentifier
    ) != nil
    static let hasCloudKitContainer = hasAppGroup
}

enum AppStoreSelection: Equatable {
    case production
    case ephemeralUITesting
    case namedUITesting(token: String)
}

private enum UITestingStoreError: Error {
    case missingToken
    case invalidToken
}

struct AppStartupFailure {
    let underlyingError: any Error
}

enum AppStartupState {
    case ready(AppDependencies)
    case failed(AppStartupFailure)
}

#if DEBUG
@MainActor
private final class FailingLifecycleMutationRepository:
    SubscriptionRepository
{
    private let base: any SubscriptionRepository

    init(base: any SubscriptionRepository) {
        self.base = base
    }

    func createSubscription(_ subscription: Subscription) throws {
        try base.createSubscription(subscription)
    }

    func updateSubscription(_ subscription: Subscription) throws {
        throw Failure.injected
    }

    func deleteSubscription(id: UUID) throws {
        throw Failure.injected
    }

    func listSubscriptions() throws -> [Subscription] {
        try base.listSubscriptions()
    }

    func subscription(id: UUID) throws -> Subscription? {
        try base.subscription(id: id)
    }

    private enum Failure: Error {
        case injected
    }
}
#endif
