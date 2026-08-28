import EventKit
import AppIntents
import SwiftData
import SubscriptionCore
import SwiftUI

@main
@MainActor
struct SubscriptionManagerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let startupState: AppStartupState
    #if os(macOS)
    private let macWindowRouter: MacWindowRouter
    #endif

    @MainActor
    init() {
        startupState = AppDependencies.live()
        #if os(macOS)
        macWindowRouter = MacWindowRouter()
        #endif
        if case .ready(let dependencies) = startupState {
            AppDependencyManager.shared.add(
                dependency: SubscriptionIntentService(
                    workspace: dependencies.workspace
                )
            )
        }
    }

    var body: some Scene {
        WindowGroup(id: "main-window") {
            rootContent
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
                await rescheduleNotifications(workspace: dependencies.workspace)
            }
        }
        #if os(macOS)
        .commands { MacWindowCommands() }
        #endif
        #if os(macOS)
        MacMenuBarScene(
            workspace: menuBarWorkspace,
            router: macWindowRouter
        )
        #endif
    }

    #if os(macOS)
    private var menuBarWorkspace: SubscriptionWorkspace? {
        guard case .ready(let dependencies) = startupState else {
            return nil
        }
        return dependencies.workspace
    }
    #endif

    @ViewBuilder
    private var rootContent: some View {
        Group {
            switch startupState {
            case .ready(let dependencies):
                #if os(macOS)
                MacLibraryView(
                    workspace: dependencies.workspace,
                    router: macWindowRouter
                )
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
        #if DEBUG
        .overlay {
            if isUITesting {
                AppearanceDebugProbe()
                    .allowsHitTesting(false)
            }
        }
        #endif
        .preferredColorScheme(rootPreferredColorScheme)
    }

    #if DEBUG
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }
    #endif

    private var rootPreferredColorScheme: ColorScheme? {
        guard case .ready(let dependencies) = startupState else {
            return nil
        }
        let appearanceMode: AppearanceMode
        switch dependencies.workspace.setupState {
        case .needsSetup(let preferences),
             .completed(let preferences),
             .skipped(let preferences),
             .failed(let preferences),
             .configurationSaveFailed(let preferences):
            appearanceMode = preferences.appearanceMode
        case .notLoaded, .loadFailed:
            appearanceMode = .system
        }
        switch appearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private let notificationScheduler = RenewalNotificationScheduler()

    private func rescheduleNotifications(
        workspace: SubscriptionWorkspace
    ) async {
        let subscriptions = (try? workspace.subscriptions()) ?? []
        await notificationScheduler.reschedule(subscriptions: subscriptions)
    }

}

#if DEBUG
private struct AppearanceDebugProbe: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("appearance.debug.probe")
            .accessibilityValue(colorScheme == .dark ? "dark" : "light")
    }
}
#endif

#if os(macOS)
enum MacWindowCommand {
    static let add = Notification.Name("MacWindowCommand.add")
    static let edit = Notification.Name("MacWindowCommand.edit")
    static let archive = Notification.Name("MacWindowCommand.archive")
    static let restore = Notification.Name("MacWindowCommand.restore")
    static let delete = Notification.Name("MacWindowCommand.delete")
    static let search = Notification.Name("MacWindowCommand.search")
    static let settings = Notification.Name("MacWindowCommand.settings")
}

private struct MacSubscriptionCommandContext: Equatable {
    let targetID: UUID
    let scope: SubscriptionLibraryScope
    let selectionCount: Int

    var canEdit: Bool {
        selectionCount == 1
    }

    var canArchive: Bool {
        scope == .current && selectionCount > 0
    }

    var canRestore: Bool {
        scope == .archived && selectionCount > 0
    }

    var canDelete: Bool {
        selectionCount == 1
    }
}

private struct MacSubscriptionCommandContextKey: FocusedValueKey {
    typealias Value = MacSubscriptionCommandContext
}

private extension FocusedValues {
    var subscriptionCommandContext: MacSubscriptionCommandContext? {
        get { self[MacSubscriptionCommandContextKey.self] }
        set { self[MacSubscriptionCommandContextKey.self] = newValue }
    }
}

struct MacWindowCommandTarget {
    static func matches(
        notificationObject: Any?,
        targetID: UUID
    ) -> Bool {
        notificationObject as? UUID == targetID
    }
}

private struct MacWindowCommands: Commands {
    @FocusedValue(\.subscriptionCommandContext)
    private var subscriptionCommandContext

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Subscription") { post(MacWindowCommand.add) }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(subscriptionCommandContext == nil)
        }
        CommandMenu("Subscription") {
            Button("Edit") { post(MacWindowCommand.edit) }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(subscriptionCommandContext?.canEdit != true)
            Button("Archive") { post(MacWindowCommand.archive) }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(subscriptionCommandContext?.canArchive != true)
            Button("Restore") { post(MacWindowCommand.restore) }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(subscriptionCommandContext?.canRestore != true)
            Divider()
            Button("Delete", role: .destructive) {
                post(MacWindowCommand.delete)
            }
            .disabled(subscriptionCommandContext?.canDelete != true)
        }
        CommandGroup(after: .toolbar) {
            Button("Search Subscriptions") { post(MacWindowCommand.search) }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(subscriptionCommandContext == nil)
            Button("Settings") { post(MacWindowCommand.settings) }
                .keyboardShortcut(",", modifiers: [.command])
                .disabled(subscriptionCommandContext == nil)
        }
    }

    private func post(_ name: Notification.Name) {
        guard let targetID = subscriptionCommandContext?.targetID else {
            return
        }
        NotificationCenter.default.post(name: name, object: targetID)
    }
}

private struct MacLibraryView: View {
    @Environment(\.locale) private var locale
    let workspace: SubscriptionWorkspace
    @ObservedObject var router: MacWindowRouter

    @State private var scope: SubscriptionLibraryScope = .current
    @State private var librarySnapshot: SubscriptionLibraryState =
        .loading(.current)
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var sort: SubscriptionTableSort = .serviceName
    @State private var ascending = true
    @State private var selection: Set<UUID> = []
    @State private var addPresentation = MacAddPresentationState()
    @State private var isSetupPresented = false
    @State private var isPreferencesPresented = false
    @State private var pinActionFailed = false
    @State private var subscriptionPendingDeletion: SubscriptionSummary?
    @State private var directActionError:
        SubscriptionLifecycleActionError?
    @State private var commandTargetID = UUID()

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
                .searchable(
                    text: $searchText,
                    isPresented: $isSearchPresented,
                    prompt: "Search Subscriptions"
                )
                .toolbar {
                    ToolbarItemGroup {
                        Button("Add Subscription", systemImage: "plus") {
                            addPresentation.present(
                                from: .toolbar,
                                scope: scope
                            )
                        }
                        Menu("Sort", systemImage: "arrow.up.arrow.down") {
                            ForEach(SubscriptionTableSort.allCases, id: \.rawValue) { value in
                                Button {
                                    if sort == value {
                                        ascending.toggle()
                                    } else {
                                        sort = value
                                        ascending = true
                                    }
                                } label: {
                                    Label {
                                        Text(sortTitle(for: value))
                                    } icon: {
                                        if sort == value {
                                            Image(
                                                systemName: ascending
                                                    ? "arrow.up"
                                                    : "arrow.down"
                                            )
                                        }
                                    }
                                }
                                .accessibilityValue(
                                    sort == value
                                        ? LocalizedStringKey("Selected")
                                        : LocalizedStringKey("Not selected")
                                )
                                .accessibilityAddTraits(
                                    sort == value ? .isSelected : []
                                )
                            }
                        }

                        if scope == .current {
                            Button("Archive", systemImage: "archivebox") {
                                archiveSelection()
                            }
                            .disabled(selection.isEmpty)
                        } else {
                            Button(
                                "Restore",
                                systemImage: "arrow.uturn.backward"
                            ) {
                                restoreSelection()
                            }
                            .disabled(selection.isEmpty)
                        }

                        Button(
                            "Delete",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            beginDeletingSelection()
                        }
                        .disabled(selection.count != 1)

                        if scope == .current {
                            if selectedSubscriptionsArePinned {
                                Button("Unpin", systemImage: "pin.slash") {
                                    pinSelection(pinned: false)
                                }
                                .disabled(selection.isEmpty)
                            } else {
                                Button("Pin", systemImage: "pin") {
                                    pinSelection(pinned: true)
                                }
                                .disabled(selection.isEmpty)
                            }
                        }
                    }
                }
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(
            \.subscriptionCommandContext,
            MacSubscriptionCommandContext(
                targetID: commandTargetID,
                scope: scope,
                selectionCount: selection.count
            )
        )
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
                if directActionError == nil {
                    selection.remove(subscription.id)
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
        .sheet(isPresented: Binding(
            get: { addPresentation.isPresented },
            set: { isPresented in
                if !isPresented {
                    addPresentation.dismiss()
                }
            }
        )) {
            CatalogAddFlowView(workspace: workspace) {
                addPresentation.complete { completedScope in
                    reloadLibrary(scope: completedScope)
                }
            }
                .frame(minWidth: 520, minHeight: 560)
        }
        .sheet(isPresented: $isPreferencesPresented) {
            UserPreferencesView(workspace: workspace) {}
                .frame(minWidth: 480, minHeight: 460)
        }
        .sheet(isPresented: $isSetupPresented) {
            FirstRunSetupView(workspace: workspace) {
                isSetupPresented = false
            }
                .frame(minWidth: 520, minHeight: 560)
        }
        .task {
            workspace.loadCatalog(locale: locale)
            workspace.reconcileCatalogAssociations(locale: locale)
            loadInitialSetupState()
            applyPendingRoute()
        }
        .onChange(of: scope) {
            selection.removeAll()
            reloadLibrary()
        }
        .onChange(of: workspace.libraryState) { _, state in
            guard libraryScope(of: state) == scope else { return }
            librarySnapshot = state
        }
        .onChange(of: workspace.setupState) { _, state in
            synchronizeSetupPresentation(for: state)
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.add)) { notification in
            guard handlesCommand(notification) else { return }
            addPresentation.present(from: .command, scope: scope)
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.edit)) { notification in
            guard handlesCommand(notification) else { return }
            beginEditingSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.archive)) { notification in
            guard handlesCommand(notification) else { return }
            archiveSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.restore)) { notification in
            guard handlesCommand(notification) else { return }
            restoreSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.delete)) { notification in
            guard handlesCommand(notification) else { return }
            beginDeletingSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.search)) { notification in
            guard handlesCommand(notification) else { return }
            isSearchPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: MacWindowCommand.settings)) { notification in
            guard handlesCommand(notification) else { return }
            isPreferencesPresented = true
        }
        .onChange(of: router.destination) { _, _ in
            applyPendingRoute()
        }
        .allowsHitTesting(!setupLoadFailed)
        .overlay {
            if setupLoadFailed {
                SetupLoadFailureView(onRetry: loadInitialSetupState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        switch librarySnapshot {
        case .loaded(let stateScope, _) where stateScope == scope:
            Table(visibleSummaries, selection: $selection) {
                TableColumn("Service") { summary in
                    Text(summary.serviceName)
                        .accessibilityValue(
                            summary.pinnedAt == nil ? Text("") : Text("Pinned")
                        )
                        .contextMenu {
                            if scope == .current {
                                if summary.pinnedAt == nil {
                                    Button("Pin", systemImage: "pin") {
                                        updatePin(
                                            id: summary.id,
                                            pinned: true
                                        )
                                    }
                                } else {
                                    Button(
                                        "Unpin",
                                        systemImage: "pin.slash"
                                    ) {
                                        updatePin(
                                            id: summary.id,
                                            pinned: false
                                        )
                                    }
                                }
                                Divider()
                                Button("Archive", systemImage: "archivebox") {
                                    updateLifecycle(id: summary.id) {
                                        workspace.archive(id: summary.id)
                                    }
                                }
                            } else {
                                Button(
                                    "Restore",
                                    systemImage: "arrow.uturn.backward"
                                ) {
                                    updateLifecycle(id: summary.id) {
                                        workspace.restore(id: summary.id)
                                    }
                                }
                            }
                            Divider()
                            Button(
                                "Delete",
                                systemImage: "trash",
                                role: .destructive
                            ) {
                                beginDirectAction()
                                subscriptionPendingDeletion = summary
                            }
                        }
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
                    Text(formattedMoney(summary.amount))
                }
            }
            .accessibilityIdentifier("mac.library.table")
        case .empty(let stateScope) where stateScope == scope:
            ContentUnavailableView(
                scope == .current
                    ? LocalizedStringKey("No Subscriptions")
                    : LocalizedStringKey("No Archived Subscriptions"),
                systemImage: scope == .current ? "rectangle.stack" : "archivebox"
            )
        case .failed(let stateScope) where stateScope == scope:
            ContentUnavailableView(
                "Couldn’t Load Subscriptions",
                systemImage: "exclamationmark.triangle"
            )
        case .loading(let stateScope) where stateScope == scope:
            ProgressView("Loading Subscriptions")
        default:
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
        guard case .loaded(let stateScope, let summaries) = librarySnapshot,
              stateScope == scope
        else {
            return []
        }
        return SubscriptionTableQuery(
            searchText: searchText,
            sort: sort,
            ascending: ascending
        )
        .apply(to: summaries, locale: locale)
    }

    private func reloadLibrary(scope targetScope: SubscriptionLibraryScope? = nil) {
        let targetScope = targetScope ?? scope
        workspace.loadLibrary(scope: targetScope)
        librarySnapshot = workspace.libraryState
    }

    private func loadInitialSetupState() {
        reloadLibrary(scope: .current)
        let currentLibraryState = librarySnapshot
        reloadLibrary(scope: .archived)
        let archivedLibraryState = librarySnapshot
        reloadLibrary(scope: scope)
        workspace.initializeSetup(
            currentLibraryState: currentLibraryState,
            archivedLibraryState: archivedLibraryState
        )
        synchronizeSetupPresentation()
    }

    private func libraryScope(
        of state: SubscriptionLibraryState
    ) -> SubscriptionLibraryScope {
        switch state {
        case .loading(let stateScope),
             .empty(let stateScope),
             .loaded(let stateScope, _),
             .failed(let stateScope):
            stateScope
        }
    }

    private func synchronizeSetupPresentation(
        for state: SetupState? = nil
    ) {
        isSetupPresented = SetupSheetPresentation.shouldPresent(
            for: state ?? workspace.setupState,
            permitsSetupPresentation: !ProcessInfo.processInfo.arguments
                .contains("--ui-testing")
        )
    }

    private var setupLoadFailed: Bool {
        if case .loadFailed = workspace.setupState {
            return true
        }
        return false
    }

    private var selectedSubscriptionsArePinned: Bool {
        let selectedSummaries = visibleSummaries.filter {
            selection.contains($0.id)
        }
        return !selectedSummaries.isEmpty
            && selectedSummaries.allSatisfy { $0.pinnedAt != nil }
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
        updateSelection(using: workspace.archive)
    }

    private func restoreSelection() {
        guard scope == .archived else { return }
        updateSelection(using: workspace.restore)
    }

    private func pinSelection(pinned: Bool) {
        guard scope == .current else { return }
        var failed = false
        selection.forEach {
            workspace.setPinned(id: $0, pinned: pinned)
            failed = failed || workspace.lifecycleActionError != nil
        }
        pinActionFailed = failed
        reloadLibrary()
    }

    private func updatePin(id: UUID, pinned: Bool) {
        workspace.clearLifecycleActionError()
        workspace.setPinned(id: id, pinned: pinned)
        pinActionFailed = workspace.lifecycleActionError != nil
        if !pinActionFailed {
            reloadLibrary()
        }
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

    private func beginDeletingSelection() {
        guard selection.count == 1,
              let selectedID = selection.first,
              let subscription = visibleSummaries.first(where: {
                  $0.id == selectedID
              })
        else { return }
        beginDirectAction()
        subscriptionPendingDeletion = subscription
    }

    private func updateSelection(
        using action: (UUID) -> Void
    ) {
        var failedIDs: Set<UUID> = []
        var capturedError: SubscriptionLifecycleActionError?
        selection.forEach { id in
            workspace.clearLifecycleActionError()
            action(id)
            if let error = workspace.lifecycleActionError {
                failedIDs.insert(id)
                capturedError = capturedError ?? error
            }
        }
        directActionError = capturedError
        reloadLibrary()
        selection = failedIDs
    }

    private func updateLifecycle(
        id: UUID,
        action: () -> Void
    ) {
        performDirectAction(action)
        if directActionError == nil {
            selection.remove(id)
        }
    }

    private func beginDirectAction() {
        directActionError = nil
        workspace.clearLifecycleActionError()
    }

    private func performDirectAction(_ action: () -> Void) {
        beginDirectAction()
        action()
        directActionError = workspace.lifecycleActionError
        if directActionError == nil {
            reloadLibrary()
        }
    }

    private func dismissDirectActionError() {
        directActionError = nil
        workspace.clearLifecycleActionError()
    }

    private func handlesCommand(_ notification: Notification) -> Bool {
        !setupLoadFailed && MacWindowCommandTarget.matches(
            notificationObject: notification.object,
            targetID: commandTargetID
        )
    }

    private func beginEditingSelection() {
        guard selection.count == 1, let id = selection.first else { return }
        workspace.loadSubscription(id: id)
        workspace.beginEditing()
    }

    private func applyPendingRoute() {
        switch router.takeDestination() {
        case .none, .open:
            break
        case .quickAdd:
            addPresentation.present(from: .quickAdd, scope: scope)
        }
    }
}
#endif
