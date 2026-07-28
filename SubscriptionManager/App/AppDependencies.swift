import Foundation
import SwiftData
import SubscriptionCore

@MainActor
struct AppDependencies {
    let modelContainer: ModelContainer
    let workspace: SubscriptionWorkspace

    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppStartupState {
        let schema = Schema([SubscriptionRecord.self])
        let usesIsolatedStore = arguments.contains("--ui-testing")

        return make {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: usesIsolatedStore
            )
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        }
    }

    static func make(
        modelContainer: () throws -> ModelContainer
    ) -> AppStartupState {
        do {
            let modelContainer = try modelContainer()
            let repository = SwiftDataSubscriptionRepository(
                modelContainer: modelContainer
            )
            return .ready(
                AppDependencies(
                    modelContainer: modelContainer,
                    workspace: SubscriptionWorkspace(repository: repository)
                )
            )
        } catch {
            return .failed(AppStartupFailure(underlyingError: error))
        }
    }
}

struct AppStartupFailure {
    let underlyingError: any Error
}

enum AppStartupState {
    case ready(AppDependencies)
    case failed(AppStartupFailure)
}
