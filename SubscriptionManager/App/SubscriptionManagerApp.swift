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
                #if os(macOS)
                MacLibraryView(workspace: dependencies.workspace)
                    .modelContainer(dependencies.modelContainer)
                #else
                LibraryView(workspace: dependencies.workspace)
                    .modelContainer(dependencies.modelContainer)
                #endif
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

#if os(macOS)
private struct MacLibraryView: View {
    let workspace: SubscriptionWorkspace

    @State private var scope: SubscriptionLibraryScope = .current
    @State private var searchText = ""
    @State private var sort: SubscriptionTableSort = .serviceName
    @State private var ascending = true
    @State private var selection: Set<UUID> = []
    @State private var isAddingSubscription = false

    var body: some View {
        NavigationSplitView {
            List(selection: $scope) {
                Label("Subscriptions", systemImage: "rectangle.stack")
                    .tag(SubscriptionLibraryScope.current)
                Label("Archived", systemImage: "archivebox")
                    .tag(SubscriptionLibraryScope.archived)
            }
            .navigationTitle("Subscription Manager")
        } content: {
            tableContent
                .navigationTitle(scope == .current ? "Subscriptions" : "Archived")
                .searchable(text: $searchText, prompt: "Search Subscriptions")
                .toolbar {
                    ToolbarItemGroup {
                        Button("Add Subscription", systemImage: "plus") {
                            isAddingSubscription = true
                        }
                        .keyboardShortcut("n", modifiers: [.command])

                        Menu("Sort", systemImage: "arrow.up.arrow.down") {
                            ForEach(SubscriptionTableSort.allCases, id: \.rawValue) { value in
                                Button(sortTitle(for: value)) {
                                    if sort == value {
                                        ascending.toggle()
                                    } else {
                                        sort = value
                                        ascending = true
                                    }
                                }
                            }
                        }

                        Button("Archive", systemImage: "archivebox") {
                            selection.forEach(workspace.archive)
                            workspace.loadLibrary(scope: scope)
                            selection.removeAll()
                        }
                        .disabled(scope != .current || selection.isEmpty)
                    }
                }
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $isAddingSubscription) {
            AddSubscriptionView(workspace: workspace)
                .frame(minWidth: 520, minHeight: 560)
        }
        .task {
            workspace.loadLibrary(scope: scope)
        }
        .onChange(of: scope) {
            selection.removeAll()
            workspace.loadLibrary(scope: scope)
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        switch workspace.libraryState {
        case .loaded(_, let summaries):
            Table(visibleSummaries, selection: $selection) {
                TableColumn("Service") { summary in
                    Text(summary.serviceName)
                }
                TableColumn("Plan") { summary in
                    Text(summary.plan)
                }
                TableColumn("Category") { summary in
                    Text(summary.category)
                }
                TableColumn("Next Renewal") { summary in
                    Text(summary.confirmedNextRenewal, format: .dateTime.year().month().day())
                }
                TableColumn("Amount") { summary in
                    Text(formattedMoney(summary.originalAmount))
                }
            }
            .accessibilityIdentifier("mac.library.table")
        case .empty:
            ContentUnavailableView(
                scope == .current ? "No Subscriptions" : "No Archived Subscriptions",
                systemImage: scope == .current ? "rectangle.stack" : "archivebox"
            )
        case .failed:
            ContentUnavailableView(
                "Couldn’t Load Subscriptions",
                systemImage: "exclamationmark.triangle"
            )
        case .loading:
            ProgressView("Loading Subscriptions")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if selection.count == 1, let id = selection.first {
            SubscriptionDetailView(workspace: workspace, subscriptionID: id)
        } else if selection.count > 1 {
            ContentUnavailableView(
                "Multiple Subscriptions Selected",
                systemImage: "checklist",
                description: Text("Choose one subscription to inspect its details.")
            )
        } else {
            ContentUnavailableView(
                "Select a Subscription",
                systemImage: "sidebar.right",
                description: Text("Choose a row to inspect and edit it.")
            )
        }
    }

    private var visibleSummaries: [SubscriptionSummary] {
        guard case .loaded(_, let summaries) = workspace.libraryState else {
            return []
        }
        return SubscriptionTableQuery(
            searchText: searchText,
            sort: sort,
            ascending: ascending
        )
        .apply(to: summaries)
    }

    private func sortTitle(for value: SubscriptionTableSort) -> LocalizedStringKey {
        switch value {
        case .serviceName: "Service"
        case .plan: "Plan"
        case .category: "Category"
        case .nextRenewal: "Next Renewal"
        case .amount: "Amount"
        }
    }
}
#endif
