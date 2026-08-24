import SubscriptionCore
import SwiftUI

struct ScopedLibraryView: View {
    let workspace: SubscriptionWorkspace
    let scope: SubscriptionLibraryScope
    let onAddSubscription: () -> Void
    let onPreferences: () -> Void
    @State private var pinActionFailed = false
    @State private var selectedSubscription: SubscriptionSummary?
    @State private var subscriptionPendingDeletion: SubscriptionSummary?
    @State private var directActionError:
        SubscriptionLifecycleActionError?

    var body: some View {
        libraryContent
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if scope == .current {
                    settingsToolbarItem
                    addToolbarItem
                }
            }
            .task(id: scope) {
                loadLibraryIfNeeded()
            }
            .onAppear {
                loadLibraryIfNeeded()
            }
            .sheet(item: $selectedSubscription) { subscription in
                NavigationStack {
                    SubscriptionDetailView(
                        workspace: workspace,
                        subscriptionID: subscription.id
                    )
                }
                .presentationBackground(.background)
                .presentationCornerRadius(28)
            }
            .alert(
                deletionConfirmationTitle,
                isPresented: Binding(
                    get: {
                        subscriptionPendingDeletion != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            subscriptionPendingDeletion = nil
                        }
                    }
                ),
                presenting: subscriptionPendingDeletion
            ) { subscription in
                Button("Delete Permanently", role: .destructive) {
                    subscriptionPendingDeletion = nil
                    performDirectAction {
                        workspace.deletePermanently(id: subscription.id)
                    }
                }
                Button("Cancel", role: .cancel) {
                    subscriptionPendingDeletion = nil
                }
            } message: { _ in
                Text(
                    LocalizedStringKey(
                        "This permanently removes its schedule, notes, "
                            + "lifecycle details, and payment history. This "
                            + "action cannot be undone."
                    )
                )
            }
            .alert(
                "Couldn’t Update Pin",
                isPresented: $pinActionFailed
            ) {
                Button("OK") {
                    workspace.clearLifecycleActionError()
                }
            } message: {
                Text("The subscription stayed unchanged. Try again.")
            }
            .alert(
                "Couldn’t Complete Action",
                isPresented: directActionErrorIsPresented,
                presenting: directActionError
            ) { _ in
                Button("OK") {
                    dismissDirectActionError()
                }
            } message: { error in
                Text(lifecycleActionErrorText(error))
            }
    }

    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            settingsButton
        }
        #else
        ToolbarItem(placement: .topBarLeading) {
            settingsButton
        }
        #endif
    }

    private var settingsButton: some View {
        Button("Settings", systemImage: "gearshape") {
            onPreferences()
        }
        .accessibilityIdentifier("library.settings")
    }

    private var navigationTitle: LocalizedStringKey {
        switch scope {
        case .current:
            "My Subscriptions"
        case .archived:
            "Archived"
        }
    }

    @ToolbarContentBuilder
    private var addToolbarItem: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            addButton
        }
        #else
        ToolbarItem(placement: .topBarTrailing) {
            addButton
        }
        #endif
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
                subscriptionRow(subscription)
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

    @ViewBuilder
    private func subscriptionRow(
        _ subscription: SubscriptionSummary
    ) -> some View {
        let row = Button {
            selectedSubscription = subscription
        } label: {
            SubscriptionRow(subscription: subscription)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(
            "\(subscription.serviceName), \(subscription.plan), "
                + "\(formattedMoney(subscription.amount)), "
                + localizedSubscriptionStatus(subscription.status)
        )
        .accessibilityIdentifier("subscription.row")

        #if os(iOS)
        if scope == .current {
            row
                .accessibilityValue(
                    subscription.pinnedAt == nil ? Text("") : Text("Pinned")
                )
                .swipeActions(
                    edge: .leading,
                    allowsFullSwipe: true
                ) {
                    Button {
                        updatePin(subscription)
                    } label: {
                        if subscription.pinnedAt == nil {
                            Label("Pin", systemImage: "pin")
                        } else {
                            Label("Unpin", systemImage: "pin.slash")
                        }
                    }
                    .tint(.orange)
                    .accessibilityIdentifier(
                        subscription.pinnedAt == nil
                            ? "subscription.pin"
                            : "subscription.unpin"
                    )
                }
                .swipeActions(
                    edge: .trailing,
                    allowsFullSwipe: false
                ) {
                    trailingActions(for: subscription)
                }
        } else {
            row.swipeActions(
                edge: .trailing,
                allowsFullSwipe: true
            ) {
                trailingActions(for: subscription)
            }
        }
        #else
        row
        #endif
    }

    private func updatePin(_ subscription: SubscriptionSummary) {
        workspace.clearLifecycleActionError()
        workspace.setPinned(
            id: subscription.id,
            pinned: subscription.pinnedAt == nil
        )
        pinActionFailed = workspace.lifecycleActionError != nil
    }

    @ViewBuilder
    private func trailingActions(
        for subscription: SubscriptionSummary
    ) -> some View {
        if scope == .current {
            Button {
                performDirectAction {
                    workspace.archive(id: subscription.id)
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.blue)
            .accessibilityIdentifier("subscription.archive")

            deleteButton(for: subscription)
        } else {
            deleteButton(for: subscription)

            Button {
                performDirectAction {
                    workspace.restore(id: subscription.id)
                }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
            .accessibilityIdentifier("subscription.restore")
        }
    }

    private func deleteButton(
        for subscription: SubscriptionSummary
    ) -> some View {
        Button(role: .destructive) {
            beginDirectAction()
            subscriptionPendingDeletion = subscription
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("subscription.delete")
    }

    private var deletionConfirmationTitle: LocalizedStringKey {
        guard let subscriptionPendingDeletion else {
            return "Permanently Delete"
        }
        return "Permanently Delete “\(subscriptionPendingDeletion.serviceName)” (\(subscriptionPendingDeletion.plan))?"
    }

    private var directActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: {
                directActionError != nil
            },
            set: { isPresented in
                if !isPresented {
                    dismissDirectActionError()
                }
            }
        )
    }

    private func beginDirectAction() {
        directActionError = nil
        workspace.clearLifecycleActionError()
    }

    private func performDirectAction(_ action: () -> Void) {
        beginDirectAction()
        action()
        directActionError = workspace.lifecycleActionError
    }

    private func dismissDirectActionError() {
        directActionError = nil
        workspace.clearLifecycleActionError()
    }

    private func loadLibraryIfNeeded() {
        let loadedScope: SubscriptionLibraryScope? =
            switch workspace.libraryState {
        case .loading(let scope),
             .empty(let scope),
             .loaded(let scope, _):
            scope
        case .failed:
            nil
        }
        guard loadedScope != scope else { return }
        workspace.loadLibrary(scope: scope)
    }

}

enum LibrarySheet: Identifiable {
    case addSubscription(UUID)

    var id: UUID {
        switch self {
        case .addSubscription(let id): id
        }
    }
}
