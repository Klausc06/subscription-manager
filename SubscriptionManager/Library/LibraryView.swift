import SubscriptionCore
import SwiftUI

struct LibraryView: View {
    let workspace: SubscriptionWorkspace
    @State private var presentedSheet: LibrarySheet?

    var body: some View {
        NavigationStack {
            libraryContent
                .navigationTitle("Subscriptions")
                .navigationDestination(for: UUID.self) { subscriptionID in
                    SubscriptionDetailView(
                        workspace: workspace,
                        subscriptionID: subscriptionID
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        addButton
                    }
                }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addSubscription:
                NavigationStack {
                    AddSubscriptionView(workspace: workspace)
                }
            }
        }
        .task {
            workspace.loadLibrary()
        }
    }

    private var addButton: some View {
        Button("Add Subscription", systemImage: "plus") {
            presentedSheet = .addSubscription
        }
        .accessibilityIdentifier("subscription.add")
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
            } actions: {
                addButton
            }
            .accessibilityIdentifier("library.empty-state")

        case let .loaded(_, subscriptions):
            List(subscriptions) { subscription in
                NavigationLink(value: subscription.id) {
                    SubscriptionRow(subscription: subscription)
                }
                .accessibilityLabel(
                    "\(subscription.serviceName), \(subscription.plan), "
                        + formattedMoney(subscription.originalAmount)
                )
                .accessibilityIdentifier("subscription.row")
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

private enum LibrarySheet: String, Identifiable {
    case addSubscription

    var id: String { rawValue }
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
    func createSubscription(_ subscription: Subscription) throws {}

    func updateSubscription(_ subscription: Subscription) throws {}

    func listSubscriptions() throws -> [Subscription] {
        []
    }

    func subscription(id: UUID) throws -> Subscription? {
        nil
    }
}
