import SwiftData
import SubscriptionCore
import SwiftUI

@main
@MainActor
struct SubscriptionManagerApp: App {
    private let dependencies: AppDependencies

    init() {
        dependencies = AppDependencies.live()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(workspace: dependencies.workspace)
        }
        .modelContainer(dependencies.modelContainer)
    }
}
