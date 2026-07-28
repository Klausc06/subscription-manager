import SwiftData
import SubscriptionCore
import SwiftUI

@main
@MainActor
struct SubscriptionManagerApp: App {
    private let startupState: AppStartupState

    init() {
        startupState = AppDependencies.live()
    }

    var body: some Scene {
        WindowGroup {
            switch startupState {
            case .ready(let dependencies):
                LibraryView(workspace: dependencies.workspace)
                    .modelContainer(dependencies.modelContainer)
            case .failed:
                ContentUnavailableView(
                    "library.error.title",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("library.error.description")
                )
            }
        }
    }
}
