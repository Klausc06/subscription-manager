import EventKit
import SwiftData
import SubscriptionCore
import SwiftUI

@main
@MainActor
struct SubscriptionManagerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let startupState: AppStartupState

    init() {
        startupState = AppDependencies.live()
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            .onReceive(NotificationCenter.default.publisher(
                for: .EKEventStoreChanged
            )) { _ in
                guard case .ready(let dependencies) = startupState else {
                    return
                }
                Task {
                    await dependencies.workspace.reconcileCalendarProjection(
                        locale: .current
                    )
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  case .ready(let dependencies) = startupState
            else { return }
            Task {
                await dependencies.workspace.reconcileCalendarProjection(
                    locale: .current
                )
            }
        }
        #if os(macOS)
        .commands { MacWindowCommands() }
        #endif
    }
}

#if os(macOS)
private enum MacWindowCommand {
    static let add = Notification.Name("MacWindowCommand.add")
    static let edit = Notification.Name("MacWindowCommand.edit")
    static let archive = Notification.Name("MacWindowCommand.archive")
    static let search = Notification.Name("MacWindowCommand.search")
    static let settings = Notification.Name("MacWindowCommand.settings")
}

private struct MacWindowCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Subscription") { post(MacWindowCommand.add) }
                .keyboardShortcut("n", modifiers: [.command])
        }
        CommandMenu("Subscription") {
            Button("Edit") { post(MacWindowCommand.edit) }
                .keyboardShortcut("e", modifiers: [.command])
            Button("Archive") { post(MacWindowCommand.archive) }
                .keyboardShortcut("a", modifiers: [.command, .option])
        }
        CommandGroup(after: .toolbar) {
            Button("Search Subscriptions") { post(MacWindowCommand.search) }
                .keyboardShortcut("f", modifiers: [.command])
            Button("Settings") { post(MacWindowCommand.settings) }
                .keyboardShortcut(",", modifiers: [.command])
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

private struct MacLibraryView: View {
    let workspace: SubscriptionWorkspace

    @State private var scope: SubscriptionLibraryScope = .current
    @State private var searchText = ""
    @State private var sort: SubscriptionTableSort = .serviceName
    @State private var ascending = true
    @State private var selection: Set<UUID> = []
    @State private var isAddingSubscription = false
    @State private var editingSubscription: Subscription?
    @State private var isPreferencesPresented = false
    @FocusState private var isSearchFocused: Bool

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
                .focused($isSearchFocused)
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
                            archiveSelection()
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
        .sheet(item: $editingSubscription) { subscription in
            EditSubscriptionView(workspace: workspace, subscription: subscription)
                .frame(minWidth: 520, minHeight: 560)
        }
        .sheet(isPresented: $isPreferencesPresented) {
            UserPreferencesView(workspace: workspace) {}
                .frame(minWidth: 480, minHeight: 460)
        }
        .task {
            workspace.loadLibrary(scope: scope)
        }
        .onChange(of: scope) {
            selection.removeAll()
            workspace.loadLibrary(scope: scope)
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.add)) { _ in
            isAddingSubscription = true
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.edit)) { _ in
            beginEditingSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.archive)) { _ in
            archiveSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.search)) { _ in
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.settings)) { _ in
            isPreferencesPresented = true
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        switch workspace.libraryState {
        case .loaded:
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

    private func archiveSelection() {
        guard scope == .current else { return }
        selection.forEach(workspace.archive)
        workspace.loadLibrary(scope: scope)
        selection.removeAll()
    }

    private func beginEditingSelection() {
        guard selection.count == 1, let id = selection.first else { return }
        workspace.loadSubscription(id: id)
        guard case .loaded(let subscription, _, _) = workspace.detailState else {
            return
        }
        workspace.beginEditing()
        editingSubscription = subscription
    }
}
#endif
