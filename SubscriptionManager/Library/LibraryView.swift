import SubscriptionCore
import SwiftUI

struct LibraryView: View {
    let workspace: SubscriptionWorkspace
    @State private var presentedSheet: LibrarySheet?

    var body: some View {
        NavigationStack {
            ScopedLibraryView(
                workspace: workspace,
                scope: .current,
                onAddSubscription: presentAddSubscription
            )
                .navigationDestination(for: UUID.self) { subscriptionID in
                    SubscriptionDetailView(
                        workspace: workspace,
                        subscriptionID: subscriptionID
                    )
                }
                .navigationDestination(
                    for: SubscriptionLibraryScope.self
                ) { scope in
                    ScopedLibraryView(
                        workspace: workspace,
                        scope: scope,
                        onAddSubscription: presentAddSubscription
                    )
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
    }

    private func presentAddSubscription() {
        presentedSheet = .addSubscription
    }
}

private struct ScopedLibraryView: View {
    let workspace: SubscriptionWorkspace
    let scope: SubscriptionLibraryScope
    let onAddSubscription: () -> Void

    var body: some View {
        libraryContent
            .navigationTitle(navigationTitle)
            .toolbar {
                if scope == .current {
                    ToolbarItemGroup(placement: .primaryAction) {
                        NavigationLink(
                            value: SubscriptionLibraryScope.archived
                        ) {
                            Label("Archived", systemImage: "archivebox")
                        }
                        .accessibilityIdentifier("library.archived")

                        addButton
                    }
                }
            }
            .task(id: scope) {
                workspace.loadLibrary(scope: scope)
            }
    }

    private var navigationTitle: LocalizedStringKey {
        switch scope {
        case .current:
            "Subscriptions"
        case .archived:
            "Archived"
        }
    }

    private var addButton: some View {
        Button("Add Subscription", systemImage: "plus") {
            onAddSubscription()
        }
        .accessibilityIdentifier("subscription.add")
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch workspace.libraryState {
        case .loading(let stateScope) where stateScope == scope:
            ProgressView("Loading Subscriptions")
                .accessibilityIdentifier("library.loading")

        case .empty(let stateScope) where stateScope == scope:
            ContentUnavailableView {
                Label(
                    "No Subscriptions Yet",
                    systemImage: "rectangle.stack.badge.plus"
                )
            } description: {
                Text("Your subscriptions will appear here.")
            } actions: {
                if scope == .current {
                    addButton
                }
            }
            .accessibilityIdentifier("library.empty-state")

        case let .loaded(stateScope, subscriptions) where stateScope == scope:
            List(subscriptions) { subscription in
                NavigationLink(value: subscription.id) {
                    SubscriptionRow(subscription: subscription)
                }
                .accessibilityLabel(
                    "\(subscription.serviceName), \(subscription.plan), "
                        + "\(formattedMoney(subscription.originalAmount)), "
                        + localizedSubscriptionStatus(subscription.status)
                )
                .accessibilityIdentifier("subscription.row")
            }

        case .failed(let stateScope) where stateScope == scope:
            ContentUnavailableView {
                Label(
                    "Couldn’t Load Subscriptions",
                    systemImage: "exclamationmark.triangle"
                )
            } description: {
                Text("Reopen the app to try again.")
            }
            .accessibilityIdentifier("library.failed-state")

        default:
            ProgressView("Loading Subscriptions")
                .accessibilityIdentifier("library.loading")
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

    func deleteSubscription(id: UUID) throws {}

    func listSubscriptions() throws -> [Subscription] {
        []
    }

    func subscription(id: UUID) throws -> Subscription? {
        nil
    }
}
