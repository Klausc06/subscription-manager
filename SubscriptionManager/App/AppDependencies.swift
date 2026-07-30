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
            UserPreferencesRecord.self,
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

        return make(
            failsLifecycleMutations: failsLifecycleMutations,
            seedsLegacyChatGPTPlus: seedsLegacyChatGPTPlus,
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
            let configuration: ModelConfiguration
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
                configuration = ModelConfiguration(
                    "UITesting-\(token)",
                    schema: schema,
                    url: directory.appending(path: "\(token).store"),
                    allowsSave: true,
                    cloudKitDatabase: cloudKitDatabase(
                        for: .namedUITesting(token: token)
                    )
                )
            case .ephemeralUITesting:
                configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: cloudKitDatabase(
                        for: .ephemeralUITesting,
                        hasCloudKitEntitlement: hasCloudKitEntitlement
                    )
                )
            case .production:
                configuration = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: cloudKitDatabase(
                        for: .production,
                        hasCloudKitEntitlement: hasCloudKitEntitlement
                    )
                )
            }
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        }
    }

    static func make(
        failsLifecycleMutations: Bool = false,
        seedsLegacyChatGPTPlus: Bool = false,
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
            return .ready(
                AppDependencies(
                    modelContainer: modelContainer,
                    workspace: SubscriptionWorkspace(
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
                        calendarProjectionReconciler:
                            calendarProjectionReconciler
                    )
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
