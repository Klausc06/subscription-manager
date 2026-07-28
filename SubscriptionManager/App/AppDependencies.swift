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
        for selection: AppStoreSelection
    ) -> CloudKitSelection {
        switch selection {
        case .production:
            .privateContainer(cloudKitContainerID)
        case .ephemeralUITesting, .namedUITesting:
            .disabled
        }
    }

    static func cloudKitDatabase(
        for selection: AppStoreSelection
    ) -> ModelConfiguration.CloudKitDatabase {
        switch cloudKitSelection(for: selection) {
        case .privateContainer(let containerID):
            .private(containerID)
        case .disabled:
            .none
        }
    }

    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        storeDirectory: URL? = nil
    ) -> AppStartupState {
        let schema = Schema([
            SubscriptionRecord.self,
            UserPreferencesRecord.self,
            CalendarProjectionMappingRecord.self
        ])
        let selection: AppStoreSelection
        do {
            selection = try storeSelection(arguments: arguments)
        } catch {
            return .failed(AppStartupFailure(underlyingError: error))
        }
        #if DEBUG
        let failsLifecycleMutations = arguments.contains("--ui-testing")
            && arguments.contains("--ui-testing-fail-lifecycle-mutations")
        #else
        let failsLifecycleMutations = false
        #endif

        return make(
            failsLifecycleMutations: failsLifecycleMutations,
            allowsExchangeRateNetworking: !arguments.contains("--ui-testing"),
            allowsCalendarImport: selection == .production,
            syncMonitor: selection == .production
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
                    cloudKitDatabase: cloudKitDatabase(for: .ephemeralUITesting)
                )
            case .production:
                configuration = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: cloudKitDatabase(for: .production)
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
        allowsExchangeRateNetworking: Bool = true,
        allowsCalendarImport: Bool = false,
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
            let calendarProjectionImporter:
                any CalendarProjectionImporter = allowsCalendarImport
                ? EventKitCalendarProjectionImporter(
                    modelContainer: modelContainer
                )
                : UnavailableCalendarProjectionImporter()
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
                        calendarProjectionImporter: calendarProjectionImporter
                    )
                )
            )
        } catch {
            return .failed(AppStartupFailure(underlyingError: error))
        }
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
