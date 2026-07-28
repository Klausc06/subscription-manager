import SubscriptionCore
import SwiftUI

struct LibraryView: View {
    let workspace: SubscriptionWorkspace

    var body: some View {
        NavigationStack {
            libraryContent
                .navigationTitle("Subscriptions")
        }
        .task {
            workspace.loadLibrary()
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch workspace.libraryState {
        case .loading:
            ProgressView("Loading Subscriptions")
                .accessibilityIdentifier("library.loading")

        case .empty:
            ContentUnavailableView {
                Label(
                    "No Subscriptions Yet",
                    systemImage: "rectangle.stack.badge.plus"
                )
            } description: {
                Text("Your subscriptions will appear here.")
            }
            .accessibilityIdentifier("library.empty-state")

        case let .loaded(subscriptions):
            List(subscriptions) { subscription in
                Label(
                    "Saved Subscription",
                    systemImage: "rectangle.stack"
                )
                .accessibilityIdentifier(
                    "subscription.\(subscription.id.uuidString)"
                )
            }

        case .failed:
            ContentUnavailableView {
                Label(
                    "Couldn’t Load Subscriptions",
                    systemImage: "exclamationmark.triangle"
                )
            } description: {
                Text("Reopen the app to try again.")
            }
            .accessibilityIdentifier("library.failed-state")
        }
    }
}

#Preview("Empty library") {
    LibraryView(
        workspace: SubscriptionWorkspace(
            repository: PreviewSubscriptionRepository()
        )
    )
}

@MainActor
private struct PreviewSubscriptionRepository: SubscriptionRepository {
    func listSubscriptions() throws -> [SubscriptionSummary] {
        []
    }
}
