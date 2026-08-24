import SubscriptionCore
import SwiftUI
import Charts

#if os(iOS)
import UIKit
#endif

enum SetupSheetPresentation {
    static func shouldPresent(
        for state: SetupState,
        permitsSetupPresentation: Bool
    ) -> Bool {
        permitsSetupPresentation && state.requiresSetupInteraction
    }

    static func isSetupInteractionActive(
        for state: SetupState,
        expectedSetupRevision: UInt64,
        currentSetupRevision: UInt64
    ) -> Bool {
        expectedSetupRevision == currentSetupRevision
            && state.requiresSetupInteraction
    }
}

struct LibraryView: View {
    private enum RootDestination: Hashable {
        case subscriptions
        case upcoming
        case insights
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    let workspace: SubscriptionWorkspace
    @State private var presentedSheet: LibrarySheet?
    @State private var isSetupPresented = false
    @State private var isPreferencesPresented = false
    @State private var selectedDestination: RootDestination = .subscriptions
    @State private var rootLibraryScope: SubscriptionLibraryScope = .current
    @State private var subscriptionsPath = NavigationPath()

    var body: some View {
        rootContent
        .sheet(item: $presentedSheet) { sheet in
            Group {
                switch sheet {
                case .addSubscription:
                    CatalogAddFlowView(workspace: workspace) {
                        workspace.loadLibrary(scope: .current)
                    }
                }
            }
            .presentationBackground(.background)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $isSetupPresented) {
            FirstRunSetupView(workspace: workspace) {
                isSetupPresented = false
            }
            .presentationBackground(.background)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $isPreferencesPresented) {
            UserPreferencesView(workspace: workspace) {
                isPreferencesPresented = false
                isSetupPresented = true
            }
            .presentationBackground(.background)
            .presentationCornerRadius(28)
        }
        .task {
            loadInitialState()
        }
        .onChange(of: workspace.setupState) { _, state in
            synchronizeSetupPresentation(for: state)
        }
        .onOpenURL(perform: openDeepLink)
    }

    @ViewBuilder
    private var rootContent: some View {
        if case .loadFailed = workspace.setupState {
            SetupLoadFailureView(onRetry: loadInitialState)
        } else if horizontalSizeClass == .regular {
            wideRoot
        } else {
            compactRoot
        }
    }

    private var compactRoot: some View {
        TabView(selection: $selectedDestination) {
            subscriptionsTab
                .tag(RootDestination.subscriptions)
                .tabItem {
                    Label("Subscriptions", systemImage: "rectangle.stack")
                }

            UpcomingView(workspace: workspace)
                .tag(RootDestination.upcoming)
                .tabItem {
                    Label("Upcoming", systemImage: "calendar")
                }

            InsightsView(workspace: workspace)
            .tag(RootDestination.insights)
            .tabItem {
                Label("Insights", systemImage: "chart.bar")
            }
        }
        .accessibilityIdentifier("app.tabs")
    }

    private var wideRoot: some View {
        NavigationSplitView {
            List {
                sidebarButton(
                    "Subscriptions",
                    systemImage: "rectangle.stack",
                    destination: .subscriptions
                )
                sidebarButton(
                    "Upcoming",
                    systemImage: "calendar",
                    destination: .upcoming
                )
                sidebarButton(
                    "Insights",
                    systemImage: "chart.bar",
                    destination: .insights
                )
            }
            .navigationTitle("Subscription Manager")
            .accessibilityIdentifier("root.sidebar")
        } detail: {
            selectedDestinationContent
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var selectedDestinationContent: some View {
        switch selectedDestination {
        case .subscriptions:
            subscriptionsTab
        case .upcoming:
            UpcomingView(workspace: workspace)
        case .insights:
            InsightsView(workspace: workspace)
        }
    }

    private func sidebarButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        destination: RootDestination
    ) -> some View {
        Button {
            selectedDestination = destination
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityIdentifier(sidebarIdentifier(for: destination))
        .accessibilityAddTraits(
            selectedDestination == destination ? .isSelected : []
        )
    }

    private func sidebarIdentifier(for destination: RootDestination) -> String {
        switch destination {
        case .subscriptions: "root.sidebar.subscriptions"
        case .upcoming: "root.sidebar.upcoming"
        case .insights: "root.sidebar.insights"
        }
    }

    private var subscriptionsTab: some View {
        NavigationStack(path: $subscriptionsPath) {
            ScopedLibraryView(
                workspace: workspace,
                scope: rootLibraryScope,
                onAddSubscription: presentAddSubscription,
                onPreferences: presentPreferences
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
                        onAddSubscription: presentAddSubscription,
                        onPreferences: presentPreferences
                    )
                }
        }
    }

    private func presentAddSubscription() {
        presentedSheet = .addSubscription(UUID())
    }

    private func presentPreferences() {
        isPreferencesPresented = true
    }

    private func openDeepLink(_ url: URL) {
        guard url.scheme == "subscription-manager" else { return }
        selectedDestination = .subscriptions
        rootLibraryScope = .current
        guard url.host == "subscription",
              let identifier = url.pathComponents.dropFirst().first,
              let subscriptionID = UUID(uuidString: identifier)
        else {
            subscriptionsPath = NavigationPath()
            return
        }
        subscriptionsPath = NavigationPath()
        subscriptionsPath.append(subscriptionID)
    }

    private func loadInitialState() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("--ui-testing")
        let opensArchivedLibrary = isUITesting
            && arguments.contains("--ui-testing-open-archived-library")
        let initialLibraryScope: SubscriptionLibraryScope =
            opensArchivedLibrary ? .archived : .current

        workspace.loadCatalog(locale: locale)
        workspace.reconcileCatalogAssociations(locale: locale)
        rootLibraryScope = initialLibraryScope
        workspace.loadLibrary(scope: .current)
        let currentLibraryState = workspace.libraryState
        workspace.loadLibrary(scope: .archived)
        let archivedLibraryState = workspace.libraryState
        workspace.loadLibrary(scope: initialLibraryScope)
        workspace.initializeSetup(
            currentLibraryState: currentLibraryState,
            archivedLibraryState: archivedLibraryState
        )
        synchronizeSetupPresentation()
    }

    private func synchronizeSetupPresentation(
        for state: SetupState? = nil
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        isSetupPresented = SetupSheetPresentation.shouldPresent(
            for: state ?? workspace.setupState,
            permitsSetupPresentation: !arguments.contains("--ui-testing")
                || arguments.contains("--ui-testing-onboarding")
        )
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
