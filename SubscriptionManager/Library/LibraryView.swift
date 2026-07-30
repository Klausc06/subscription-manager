import SubscriptionCore
import SwiftUI
import Charts

struct LibraryView: View {
    private enum RootDestination: Hashable {
        case subscriptions
        case upcoming
        case insights
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let workspace: SubscriptionWorkspace
    @State private var presentedSheet: LibrarySheet?
    @State private var isSetupPresented = false
    @State private var isPreferencesPresented = false
    @State private var selectedDestination: RootDestination = .subscriptions
    @State private var subscriptionsPath = NavigationPath()

    var body: some View {
        rootContent
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addSubscription:
                CatalogAddFlowView(workspace: workspace) {
                    workspace.loadLibrary(scope: .current)
                }
            }
        }
        .sheet(isPresented: $isSetupPresented) {
            FirstRunSetupView(workspace: workspace) {
                isSetupPresented = false
            }
        }
        .sheet(isPresented: $isPreferencesPresented) {
            UserPreferencesView(workspace: workspace) {
                isPreferencesPresented = false
                isSetupPresented = true
            }
        }
        .task {
            loadInitialState()
        }
        .onOpenURL(perform: openDeepLink)
    }

    @ViewBuilder
    private var rootContent: some View {
        if horizontalSizeClass == .regular {
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
                scope: .current,
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
        workspace.loadLibrary(scope: .current)
        let libraryIsEmpty: Bool
        if case .empty(.current) = workspace.libraryState {
            libraryIsEmpty = true
        } else {
            libraryIsEmpty = false
        }
        workspace.loadSetup(libraryIsEmpty: libraryIsEmpty)
        let arguments = ProcessInfo.processInfo.arguments
        let allowsUITestOnboarding = arguments.contains("--ui-testing-onboarding")
        let isUITesting = arguments.contains("--ui-testing")
        if case .needsSetup = workspace.setupState,
           !isUITesting || allowsUITestOnboarding
        {
            isSetupPresented = true
        }
    }
}

private struct InsightsView: View {
    let workspace: SubscriptionWorkspace
    @State private var mode: SpendingReportMode = .expected

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Total Mode", selection: $mode) {
                        Text("Expected").tag(SpendingReportMode.expected)
                        Text("Confirmed").tag(SpendingReportMode.confirmed)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("insights.mode")
                }

                switch workspace.insightsState {
                case .notLoaded:
                    ProgressView("Loading Insights")
                case .unavailable:
                    ContentUnavailableView(
                        "Insights Unavailable",
                        systemImage: "chart.bar.xaxis",
                        description: Text(
                            "Exchange rates are unavailable. Original subscription values are unchanged."
                        )
                    )
                    .accessibilityIdentifier("insights.unavailable")
                case .available(let insights):
                    rateStatus
                    Section("Selected Range") {
                        LabeledContent(
                            "Total",
                            value: formattedMoney(insights.selectedRangeTotal)
                        )
                        LabeledContent(
                            "Annualized",
                            value: formattedMoney(insights.annualizedTotal)
                        )
                    }
                    if !insights.categoryTotals.isEmpty {
                        Section("Spending by Category") {
                            Chart(insights.categoryTotals) { total in
                                BarMark(
                                    x: .value("Amount", total.amount.minorUnits),
                                    y: .value("Category", total.category)
                                )
                                .accessibilityLabel(
                                    "\(total.category): \(formattedMoney(total.amount))"
                                )
                            }
                            .frame(minHeight: 180)
                            .accessibilityIdentifier("insights.category-chart")
                        }
                        Section("Category Totals") {
                            ForEach(insights.categoryTotals) { total in
                                LabeledContent(
                                    total.category,
                                    value: formattedMoney(total.amount)
                                )
                            }
                        }
                        .accessibilityIdentifier("insights.text-summary")
                    }
                }
            }
            .navigationTitle("Insights")
        }
        .task(id: mode) {
            await workspace.refreshExchangeRates()
            workspace.loadInsights(
                mode: mode,
                from: Calendar.current.startOfDay(for: Date()),
                through: Calendar.current.date(
                    byAdding: .day,
                    value: 30,
                    to: Calendar.current.startOfDay(for: Date())
                ) ?? Date()
            )
        }
    }

    @ViewBuilder
    private var rateStatus: some View {
        switch workspace.exchangeRateStatus {
        case .fresh(let snapshot):
            Text("Rates updated \(snapshot.providerDate, format: .dateTime.year().month().day())")
                .accessibilityIdentifier("insights.rate-status")
        case .stale(let snapshot):
            Text("Using cached rates from \(snapshot.providerDate, format: .dateTime.year().month().day())")
                .accessibilityIdentifier("insights.rate-status")
        case .notLoaded, .unavailable:
            EmptyView()
        }
    }
}

private struct UpcomingView: View {
    private enum DateRange: String, CaseIterable, Identifiable {
        case today
        case next30Days
        case next90Days

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .today: "Today"
            case .next30Days: "Next 30 Days"
            case .next90Days: "Next 90 Days"
            }
        }

        var dayCount: Int {
            switch self {
            case .today: 0
            case .next30Days: 30
            case .next90Days: 90
            }
        }
    }

    let workspace: SubscriptionWorkspace
    @State private var dateRange: DateRange = .next30Days

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Date Range", selection: $dateRange) {
                        ForEach(DateRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("upcoming.range")
                }

                if workspace.upcomingTimeline.isEmpty {
                    ContentUnavailableView(
                        "No Upcoming Charges",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(
                            "Choose a longer date range or add a subscription."
                        )
                    )
                    .accessibilityIdentifier("upcoming.empty-state")
                } else {
                    ForEach(workspace.upcomingTimeline) { item in
                        NavigationLink(value: item.subscriptionID) {
                            UpcomingTimelineRow(item: item)
                        }
                        .accessibilityIdentifier(
                            item.kind == .expected
                                ? "upcoming.row.expected"
                                : "upcoming.row.confirmed"
                        )
                    }
                }
            }
            .navigationTitle("Upcoming")
            .navigationDestination(for: UUID.self) { subscriptionID in
                SubscriptionDetailView(
                    workspace: workspace,
                    subscriptionID: subscriptionID
                )
            }
        }
        .onAppear {
            loadTimeline()
        }
        .task(id: dateRange) {
            loadTimeline()
        }
    }

    private var rangeStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var rangeEnd: Date {
        Calendar.current.date(
            byAdding: .day,
            value: dateRange.dayCount,
            to: rangeStart
        ) ?? rangeStart
    }

    private func loadTimeline() {
        workspace.loadUpcomingTimeline(from: rangeStart, through: rangeEnd)
    }
}

private struct UpcomingTimelineRow: View {
    let item: UpcomingTimelineItem

    var body: some View {
        HStack {
            Image(
                systemName: item.kind == .expected
                    ? "calendar"
                    : "checkmark.circle"
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(item.serviceName)
                Text(statusTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(formattedMoney(item.amount))
                Text(item.date, format: .dateTime.month().day().year())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.serviceName), \(statusAccessibilityText), "
                + "\(formattedMoney(item.amount))"
        )
    }

    private var statusTitle: LocalizedStringKey {
        item.kind == .expected ? "Expected Charge" : "Confirmed Payment"
    }

    private var statusAccessibilityText: String {
        item.kind == .expected
            ? String(localized: "Expected Charge")
            : String(localized: "Confirmed Payment")
    }
}

private struct FirstRunSetupView: View {
    private enum Step {
        case preferences
        case catalog
    }

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let onFinished: () -> Void

    @State private var step: Step = .preferences
    @State private var primaryCurrency: Currency = .cny
    @State private var horizon: CalendarProjectionHorizon = .twelveMonths
    @State private var selectedPresetIDs: Set<String> = []
    @State private var confirmedPresetIDs: Set<String> = []
    @State private var navigationPath: [String] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch step {
                case .preferences:
                    preferencesContent
                case .catalog:
                    catalogContent
                }
            }
            .navigationDestination(for: String.self) { presetID in
                if let preset = presets.first(where: { $0.id == presetID }) {
                    AddSubscriptionView(
                        workspace: workspace,
                        preset: preset,
                        showsCancellationAction: false,
                        onSuccessfulSave: {
                            confirmedPresetIDs.insert(presetID)
                            navigationPath.removeAll()
                        }
                    )
                }
            }
        }
        .task {
            applyWorkspacePreferences()
        }
    }

    private var preferencesContent: some View {
        Form {
            Section {
                Text("Choose the defaults you want to use throughout the app.")
                    .foregroundStyle(.secondary)
            }

            Section("Primary Currency") {
                Picker("Primary Currency", selection: $primaryCurrency) {
                    ForEach(Currency.allCases, id: \.rawValue) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setup.primary-currency")
            }

            Section("Calendar Projection") {
                Picker("Calendar Projection", selection: $horizon) {
                    Text("6 Months").tag(CalendarProjectionHorizon.sixMonths)
                    Text("12 Months").tag(CalendarProjectionHorizon.twelveMonths)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setup.calendar-horizon")

                Text("This only saves a future planning preference. Calendar access is requested separately when you choose to import renewals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if case .failed = workspace.setupState {
                Section {
                    Text("Couldn’t save preferences. Try again.")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Set Up Your Library")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip for Now") {
                    workspace.skipSetup()
                    guard !setupPersistenceFailed else { return }
                    finish()
                }
                .accessibilityIdentifier("setup.skip")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") {
                    workspace.updatePreferences(
                        primaryCurrency: primaryCurrency,
                        calendarProjectionHorizon: horizon
                    )
                    if case .failed = workspace.setupState {
                        return
                    }
                    workspace.loadCatalog(locale: locale)
                    step = .catalog
                }
                .accessibilityIdentifier("setup.continue")
            }
        }
    }

    private var catalogContent: some View {
        List {
            Section {
                Text("Choose any services you use. You will confirm the actual plan, price, currency, and dates for each one before it is saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Catalog") {
                ForEach(presets) { preset in
                    Button {
                        toggleSelection(for: preset.id)
                    } label: {
                        HStack {
                            Label(
                                preset.serviceName.value(for: locale),
                                systemImage: preset.icon.systemImageName
                            )
                            Spacer()
                            Image(
                                systemName: selectedPresetIDs.contains(preset.id)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .accessibilityHidden(true)
                        }
                    }
                    .accessibilityValue(
                        selectedPresetIDs.contains(preset.id)
                            ? "Selected"
                            : "Not selected"
                    )
                    .accessibilityIdentifier("setup.preset.\(preset.id)")
                }
            }

            if setupPersistenceFailed {
                Section {
                    Text("Couldn’t save preferences. Try again.")
                        .foregroundStyle(.red)
                }
            }

            Section {
                NavigationLink {
                    AddSubscriptionView(
                        workspace: workspace,
                        showsCancellationAction: false
                    )
                } label: {
                    Label("Add Manually Instead", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Choose Subscriptions")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    step = .preferences
                }
                .accessibilityIdentifier("setup.back")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Actions") {
                    Button("Confirm Selected Subscriptions") {
                        confirmNextSelection()
                    }
                    .disabled(nextUnconfirmedPresetID == nil)
                    .accessibilityIdentifier("setup.confirm-selected")

                    Button("Finish Setup") {
                        workspace.completeSetup()
                        guard !setupPersistenceFailed else { return }
                        finish()
                    }
                    .disabled(!selectedPresetIDs.isSubset(of: confirmedPresetIDs))
                    .accessibilityIdentifier("setup.finish")
                }
                .accessibilityIdentifier("setup.actions")
            }
        }
        .task {
            workspace.loadCatalog(locale: locale)
            confirmedPresetIDs.formUnion(existingCatalogPresetIDs)
        }
    }

    private var presets: [CatalogPreset] {
        guard case .loaded(_, let presets) = workspace.catalogState else {
            return []
        }
        return presets
    }

    private var nextUnconfirmedPresetID: String? {
        selectedPresetIDs.sorted().first { !confirmedPresetIDs.contains($0) }
    }

    private var existingCatalogPresetIDs: Set<String> {
        guard case .loaded(_, let subscriptions) = workspace.libraryState else {
            return []
        }
        let prefix = "catalog:"
        let storedPresetIDs: Set<String> = Set(
            subscriptions.compactMap { subscription in
                let identity = subscription.serviceIdentity.rawValue
                guard identity.hasPrefix(prefix) else { return nil }
                return String(identity.dropFirst(prefix.count))
            }
        )
        return Set(storedPresetIDs.map { storedPresetID in
            presets.first(where: {
                $0.id == storedPresetID
                    || $0.legacyPresetIDs.contains(storedPresetID)
            })?.id ?? storedPresetID
        })
    }

    private func toggleSelection(for id: String) {
        if selectedPresetIDs.contains(id) {
            selectedPresetIDs.remove(id)
            confirmedPresetIDs.remove(id)
        } else {
            selectedPresetIDs.insert(id)
            if existingCatalogPresetIDs.contains(id) {
                confirmedPresetIDs.insert(id)
            }
        }
    }

    private func confirmNextSelection() {
        guard let id = nextUnconfirmedPresetID else { return }
        navigationPath.append(id)
    }

    private func applyWorkspacePreferences() {
        switch workspace.setupState {
        case .needsSetup(let preferences),
             .completed(let preferences),
             .skipped(let preferences),
             .failed(let preferences):
            primaryCurrency = preferences.primaryCurrency
            horizon = preferences.calendarProjectionHorizon
        case .notLoaded:
            break
        }
    }

    private var setupPersistenceFailed: Bool {
        if case .failed = workspace.setupState {
            return true
        }
        return false
    }

    private func finish() {
        onFinished()
        dismiss()
    }
}

private struct ScopedLibraryView: View {
    let workspace: SubscriptionWorkspace
    let scope: SubscriptionLibraryScope
    let onAddSubscription: () -> Void
    let onPreferences: () -> Void
    @State private var pinActionFailed = false

    var body: some View {
        libraryContent
            .navigationTitle(navigationTitle)
            .toolbar {
                if scope == .current {
                    settingsToolbarItem
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
            .onAppear {
                workspace.loadLibrary(scope: scope)
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
        let row = NavigationLink(value: subscription.id) {
            SubscriptionRow(subscription: subscription)
        }
        .accessibilityLabel(
            "\(subscription.serviceName), \(subscription.plan), "
                + "\(formattedMoney(subscription.originalAmount)), "
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
        } else {
            row
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
}

struct UserPreferencesView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let onResumeSetup: () -> Void

    @State private var primaryCurrency: Currency = .cny
    @State private var horizon: CalendarProjectionHorizon = .twelveMonths
    @State private var hideAmountsInCalendar = false
    @State private var menuBarModeEnabled = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Primary Currency") {
                    preferenceButton(
                        title: "CNY",
                        isSelected: primaryCurrency == .cny,
                        identifier: "preferences.currency.cny"
                    ) {
                        primaryCurrency = .cny
                    }
                    preferenceButton(
                        title: "USD",
                        isSelected: primaryCurrency == .usd,
                        identifier: "preferences.currency.usd"
                    ) {
                        primaryCurrency = .usd
                    }
                    preferenceButton(
                        title: "EUR",
                        isSelected: primaryCurrency == .eur,
                        identifier: "preferences.currency.eur"
                    ) {
                        primaryCurrency = .eur
                    }
                }

                Section("Calendar Projection") {
                    preferenceButton(
                        title: "6 Months",
                        isSelected: horizon == .sixMonths,
                        identifier: "preferences.horizon.six-months"
                    ) {
                        horizon = .sixMonths
                    }
                    preferenceButton(
                        title: "12 Months",
                        isSelected: horizon == .twelveMonths,
                        identifier: "preferences.horizon.twelve-months"
                    ) {
                        horizon = .twelveMonths
                    }
                    Toggle(
                        "Hide Amounts in Calendar",
                        isOn: $hideAmountsInCalendar
                    )
                    .accessibilityIdentifier("preferences.calendar.hide-amounts")
                    NavigationLink {
                        CalendarProjectionView(workspace: workspace)
                    } label: {
                        Label(
                            "Preview & Export ICS",
                            systemImage: "calendar.badge.plus"
                        )
                    }
                    .accessibilityIdentifier("preferences.calendar.preview")
                }

                Section("iCloud") {
                    SyncStatusView(workspace: workspace)
                }

                #if os(macOS)
                Section("Menu Bar") {
                    Toggle(
                        "Keep Subscription Manager in the Menu Bar",
                        isOn: $menuBarModeEnabled
                    )
                    .accessibilityIdentifier("preferences.menu-bar.enabled")
                    LaunchAtLoginSettingsView()
                }
                #endif

                Section("Data") {
                    NavigationLink {
                        PortableRestoreView(workspace: workspace)
                    } label: {
                        Label("Restore JSON Backup", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("preferences.portable-restore")
                    NavigationLink {
                        PortableExportView(workspace: workspace)
                    } label: {
                        Label(
                            "Export Backup & CSV",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .accessibilityIdentifier("preferences.portable-export")
                }

                if saveFailed {
                    Section {
                        Text("Couldn’t save preferences. Try again.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Run Setup Again") {
                        workspace.resumeSetup()
                        guard case .needsSetup = workspace.setupState else {
                            saveFailed = true
                            return
                        }
                        onResumeSetup()
                        dismiss()
                    }
                    .accessibilityIdentifier("preferences.resume-setup")
                }
            }
            .navigationTitle("Settings")
            .task {
                await workspace.refreshSyncStatus()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        workspace.updatePreferences(
                            primaryCurrency: primaryCurrency,
                            calendarProjectionHorizon: horizon,
                            hideAmountsInCalendar: hideAmountsInCalendar,
                            menuBarModeEnabled: menuBarModeEnabled
                        )
                        saveFailed = isSetupSaveFailure
                        if !saveFailed {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("preferences.save")
                }
            }
        }
        .task {
            applyWorkspacePreferences()
        }
    }

    private func preferenceButton(
        title: LocalizedStringKey,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(identifier)
    }

    private var isSetupSaveFailure: Bool {
        if case .failed = workspace.setupState {
            return true
        }
        return false
    }

    private func applyWorkspacePreferences() {
        switch workspace.setupState {
        case .needsSetup(let preferences),
             .completed(let preferences),
             .skipped(let preferences),
             .failed(let preferences):
            primaryCurrency = preferences.primaryCurrency
            horizon = preferences.calendarProjectionHorizon
            hideAmountsInCalendar = preferences.hideAmountsInCalendar
            menuBarModeEnabled = preferences.menuBarModeEnabled
        case .notLoaded:
            break
        }
    }
}

private struct SyncStatusView: View {
    let workspace: SubscriptionWorkspace

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if workspace.syncStatus == .requiresAttention {
                Button("Try Again") {
                    Task { await workspace.refreshSyncStatus() }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sync.status.\(identifier)")
    }

    private var title: LocalizedStringKey {
        switch workspace.syncStatus {
        case .notLoaded: "Checking iCloud"
        case .localOnly: "Stored on This Device"
        case .synchronizing: "Syncing with iCloud"
        case .current: "iCloud Up to Date"
        case .signedOut: "iCloud Signed Out"
        case .requiresAttention: "iCloud Needs Attention"
        }
    }

    private var symbol: String {
        switch workspace.syncStatus {
        case .notLoaded, .synchronizing: "arrow.triangle.2.circlepath"
        case .localOnly: "internaldrive"
        case .current: "checkmark.icloud"
        case .signedOut: "icloud.slash"
        case .requiresAttention: "exclamationmark.icloud"
        }
    }

    private var identifier: String {
        switch workspace.syncStatus {
        case .notLoaded: "checking"
        case .localOnly: "local-only"
        case .synchronizing: "synchronizing"
        case .current: "current"
        case .signedOut: "signed-out"
        case .requiresAttention: "attention"
        }
    }
}

private enum LibrarySheet: Identifiable {
    case addSubscription(UUID)

    var id: UUID {
        switch self {
        case .addSubscription(let id): id
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
