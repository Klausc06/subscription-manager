import SwiftData
import SubscriptionCore

@MainActor
struct AppDependencies {
    let modelContainer: ModelContainer
    let workspace: SubscriptionWorkspace

    static func live() -> AppDependencies {
        let schema = Schema([SubscriptionRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            let repository = SwiftDataSubscriptionRepository(
                modelContainer: modelContainer
            )
            return AppDependencies(
                modelContainer: modelContainer,
                workspace: SubscriptionWorkspace(repository: repository)
            )
        } catch {
            fatalError("Unable to create the local subscription store: \(error)")
        }
    }
}
