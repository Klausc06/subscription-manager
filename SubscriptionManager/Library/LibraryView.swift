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

private struct InsightsView: View {
    let workspace: SubscriptionWorkspace
    @State private var mode: SpendingReportMode = .expected
    @State private var isRefreshingRates = false

    var body: some View {
        NavigationStack {
            List {
                Picker("Total Mode", selection: $mode) {
                    Text("Expected").tag(SpendingReportMode.expected)
                    Text("Confirmed").tag(SpendingReportMode.confirmed)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Total Mode")
                .accessibilityIdentifier("insights.mode")
                .listRowInsets(
                    EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if isRefreshingRates, !isInsightsLoading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Updating exchange rates…")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("insights.rates-refreshing")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
            await reloadInsights(for: mode)
        }
    }

    private var isInsightsLoading: Bool {
        if case .notLoaded = workspace.insightsState { return true }
        return false
    }

    /// Renders the mode's totals from whatever snapshot is already available
    /// before awaiting the network, so switching Expected/Confirmed never
    /// blanks out or freezes on stale figures.
    private func reloadInsights(for selectedMode: SpendingReportMode) async {
        loadInsights(for: selectedMode)
        isRefreshingRates = true
        await workspace.refreshExchangeRates()
        isRefreshingRates = false
        loadInsights(for: selectedMode)
    }

    private func loadInsights(for selectedMode: SpendingReportMode) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let rangeStart = selectedMode == .expected
            ? today
            : calendar.date(
                byAdding: .day,
                value: -29,
                to: today
            ) ?? today
        let finalDay = selectedMode == .expected
            ? calendar.date(
                byAdding: .day,
                value: 29,
                to: today
            ) ?? today
            : today
        let rangeEnd = calendar.dateInterval(of: .day, for: finalDay).flatMap {
            calendar.date(
                byAdding: .nanosecond,
                value: -1,
                to: $0.end
            )
        } ?? finalDay
        workspace.loadInsights(
            mode: selectedMode,
            from: rangeStart,
            through: rangeEnd
        )
    }

    @ViewBuilder
    private var rateStatus: some View {
        switch workspace.exchangeRateStatus {
        case .fresh(let snapshot):
            rateStatusContainer(
                Text(
                    "Rates updated \(snapshot.providerDate, format: .dateTime.year().month().day())"
                )
            )
        case .stale(let snapshot):
            rateStatusContainer(
                Text(
                    "Using cached rates from \(snapshot.providerDate, format: .dateTime.year().month().day())"
                )
            )
        case .notLoaded, .unavailable:
            EmptyView()
        }
    }

    private func rateStatusContainer(_ content: Text) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.vertical, 4)
            .accessibilityIdentifier("insights.rate-status")
    }
}

private struct UpcomingView: View {
    let workspace: SubscriptionWorkspace
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var selectsFirstChargeAfterMonthChange = false
    @State private var confirmationPresentation:
        UpcomingConfirmationPresentation?
    @State private var subscriptionsByID: [UUID: Subscription] = [:]
    @State private var confirmedSourceChargeIDsBySubscription:
        [UUID: Set<ScheduledChargeID>] = [:]
    @State private var cachedProjection: UpcomingCalendarProjection?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let projection = calendarProjection
        let selectedDayItems = selectedDayItems(in: projection)
        NavigationStack {
            GeometryReader { geometry in
                List {
                    Section {
                        HStack {
                            Button {
                                moveMonth(by: -1)
                            } label: {
                                Label("Previous Month", systemImage: "chevron.left")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel("Previous Month")
                            .accessibilityIdentifier("upcoming.month.previous")
                            .buttonStyle(.borderless)

                            Spacer()
                            Text(displayedMonth, format: .dateTime.year().month(.wide))
                                .font(.headline)
                                .accessibilityIdentifier("upcoming.month.title")
                            Spacer()

                            Button {
                                moveMonth(by: 1)
                            } label: {
                                Label("Next Month", systemImage: "chevron.right")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel("Next Month")
                            .accessibilityIdentifier("upcoming.month.next")
                            .buttonStyle(.borderless)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                    }
                    .listRowInsets(
                        EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
                    )

                    monthOverview(
                        availableWidth: geometry.size.width,
                        projection: projection
                    )

                    Section {
                        if hasUpcomingFailure {
                            ContentUnavailableView(
                                "Upcoming Unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text(
                                    "Renewals could not be loaded. Try again later."
                                )
                            )
                            .accessibilityIdentifier("upcoming.agenda.failed")
                        } else if selectedDayItems.isEmpty {
                            ContentUnavailableView(
                                "No Charges This Day",
                                systemImage: "calendar",
                                description: Text(
                                    "Choose a day with a charge or another month."
                                )
                            )
                            .accessibilityIdentifier(
                                "upcoming.agenda.empty"
                            )
                        } else {
                            ForEach(selectedDayItems) { item in
                                let confirmation = confirmationContext(
                                    for: item
                                )
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    NavigationLink(value: item.subscriptionID) {
                                        UpcomingTimelineRow(
                                            item: item,
                                            billingTimeZoneIdentifier:
                                                subscriptionsByID[item.subscriptionID]?
                                                .billingSchedule.timeZoneIdentifier
                                                ?? TimeZone.autoupdatingCurrent.identifier
                                        )
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier(
                                        item.kind == .expected
                                            ? "upcoming.row.expected"
                                            : "upcoming.row.confirmed"
                                    )

                                    if let confirmation {
                                        Button {
                                            confirmationPresentation = confirmation
                                        } label: {
                                            Label(
                                                "Confirm Charge",
                                                systemImage: "checkmark.circle"
                                            )
                                            .labelStyle(.iconOnly)
                                            .frame(minWidth: 28, minHeight: 28)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(
                                            "Confirm Charge, \(item.serviceName)"
                                        )
                                        .accessibilityIdentifier(
                                            "upcoming.expected.confirm"
                                        )
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(
                            selectedDay,
                            format: .dateTime.month().day().weekday()
                        )
                        .accessibilityIdentifier("upcoming.agenda")
                    }
                    .listRowInsets(
                        EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                    )
                }
                .accessibilityIdentifier("upcoming.month")
            }
            .navigationTitle("Upcoming")
            .navigationDestination(for: UUID.self) { subscriptionID in
                SubscriptionDetailView(
                    workspace: workspace,
                    subscriptionID: subscriptionID
                )
            }
        }
        .sheet(item: $confirmationPresentation) { presentation in
            NavigationStack {
                ConfirmChargeView(
                    workspace: workspace,
                    subscription: presentation.subscription,
                    expectedOccurrence: presentation.expectedOccurrence
                )
            }
            .presentationBackground(.background)
            .presentationCornerRadius(28)
        }
        .onAppear {
            refreshSubscriptionCaches()
            loadTimeline()
        }
        .task(id: displayedMonth) {
            loadTimeline()
        }
        .onChange(of: workspace.upcomingTimeline) { _, _ in
            rebuildProjection()
        }
        .onChange(of: workspace.libraryState) { _, _ in
            refreshSubscriptionCaches()
        }
    }

    @ViewBuilder
    private func monthOverview(
        availableWidth: CGFloat,
        projection: UpcomingCalendarProjection
    ) -> some View {
#if os(iOS)
        if hasUpcomingFailure {
            Section {
                ContentUnavailableView(
                    "Upcoming Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "Renewals could not be loaded. Try again later."
                    )
                )
                .accessibilityIdentifier("upcoming.month.failed")
            }
        } else if canUseNativeMonthCalendar(availableWidth: availableWidth) {
            Section {
                UpcomingMonthCalendar(
                    selectedDay: $selectedDay,
                    displayedMonth: displayedMonth,
                    dayCounts: Dictionary(
                        uniqueKeysWithValues: projection.days.map {
                            ($0.date, $0.items.count)
                        }
                    ),
                    calendar: calendar,
                    onDisplayedMonthChange: selectMonth
                )
                .frame(maxWidth: .infinity)
                .frame(height: calendarHeight)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("upcoming.calendar")
            }
            .listRowInsets(
                EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )
        } else {
            groupedDayList(projection: projection)
        }
#else
        if hasUpcomingFailure {
            Section {
                ContentUnavailableView(
                    "Upcoming Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "Renewals could not be loaded. Try again later."
                    )
                )
                .accessibilityIdentifier("upcoming.month.failed")
            }
        } else {
            groupedDayList(projection: projection)
        }
#endif
    }

    private func groupedDayList(
        projection: UpcomingCalendarProjection
    ) -> some View {
        Section("Days") {
            if projection.days.isEmpty {
                ContentUnavailableView(
                    "No Charges This Month",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(
                        "Select another month or add a subscription."
                    )
                )
                .accessibilityIdentifier("upcoming.month.empty")
            } else {
                ForEach(projection.days) { day in
                    Button {
                        selectedDay = day.date
                    } label: {
                        HStack {
                            Text(day.date, format: .dateTime.month().day().weekday())
                            Spacer()
                            Text(day.items.count, format: .number)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier(dayIdentifier(for: day.date))
                    .accessibilityValue(
                        selectedDay == day.date ? "Selected" : ""
                    )
                    .accessibilityAddTraits(
                        selectedDay == day.date ? .isSelected : []
                    )
                }
            }
        }
    }

    private func canUseNativeMonthCalendar(availableWidth: CGFloat) -> Bool {
#if os(iOS)
        guard !dynamicTypeSize.isAccessibilitySize else { return false }
        return availableWidth >= nativeCalendarMinimumWidth
#else
        false
#endif
    }

    private var nativeCalendarMinimumWidth: CGFloat {
        // Seven readable day cells plus the list's measured horizontal insets.
        7 * 36 + 32
    }

    private var calendarHeight: CGFloat {
        // Scale calendar height for larger Dynamic Type sizes that remain
        // below the accessibility threshold (where the calendar is hidden).
        switch dynamicTypeSize {
        case .xxxLarge:
            420
        case .xxLarge:
            400
        case .xLarge:
            380
        default:
            360
        }
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var monthInterval: DateInterval? {
        calendar.dateInterval(of: .month, for: displayedMonth)
    }

    private var calendarProjection: UpcomingCalendarProjection {
        cachedProjection ?? UpcomingCalendarProjection(
            monthContaining: displayedMonth,
            items: [],
            calendar: calendar
        )
    }

    /// Rebuilds the month projection from the already-loaded timeline and
    /// subscription cache. This never touches persistence, so it is safe to
    /// run on every timeline change without re-fetching the library.
    private func rebuildProjection() {
        cachedProjection = UpcomingCalendarProjection(
            monthContaining: displayedMonth,
            items: workspace.upcomingTimeline.map { item in
                UpcomingTimelineItem(
                    id: item.id,
                    kind: item.kind,
                    subscriptionID: item.subscriptionID,
                    serviceName: item.serviceName,
                    date: billingLocalDay(
                        item.date,
                        billingTimeZoneIdentifier:
                            subscriptionsByID[item.subscriptionID]?
                            .billingSchedule.timeZoneIdentifier
                            ?? TimeZone.autoupdatingCurrent.identifier,
                        displayCalendar: calendar
                    ),
                    amount: item.amount
                )
            },
            calendar: calendar
        )
    }

    /// Fetches the subscriptions once and derives every per-row lookup the
    /// agenda needs, including confirmed-charge ID sets that used to be
    /// rebuilt inside each ForEach row.
    private func refreshSubscriptionCaches() {
        guard let subscriptions = try? workspace.subscriptions() else { return }
        var subscriptionsByID: [UUID: Subscription] = [:]
        var confirmedIDsBySubscription:
            [UUID: Set<ScheduledChargeID>] = [:]
        for subscription in subscriptions {
            subscriptionsByID[subscription.id] = subscription
            confirmedIDsBySubscription[subscription.id] = Set(
                subscription.confirmedCharges.compactMap(
                    \.sourceScheduledChargeID
                )
            )
        }
        self.subscriptionsByID = subscriptionsByID
        confirmedSourceChargeIDsBySubscription = confirmedIDsBySubscription
        rebuildProjection()
    }

    private func selectedDayItems(
        in projection: UpcomingCalendarProjection
    ) -> [UpcomingTimelineItem] {
        let selectedIDs = Set(
            projection.days.first(where: { $0.date == selectedDay })?
                .items.map(\.id) ?? []
        )
        return workspace.upcomingTimeline
            .filter { selectedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id < rhs.id
            }
    }

    private var hasUpcomingFailure: Bool {
        if case .failed = workspace.upcomingTimelineState {
            return true
        }
        return false
    }

    private func loadTimeline() {
        guard let monthInterval else { return }
        let lastDay = calendar.date(
            byAdding: .nanosecond,
            value: -1,
            to: monthInterval.end
        ) ?? monthInterval.end
        let queryStart = calendar.date(
            byAdding: .day,
            value: -2,
            to: monthInterval.start
        ) ?? monthInterval.start
        let queryEnd = calendar.date(
            byAdding: .day,
            value: 2,
            to: lastDay
        ) ?? lastDay
        workspace.loadUpcomingTimeline(
            from: queryStart,
            through: queryEnd
        )
        rebuildProjection()

        if selectsFirstChargeAfterMonthChange {
            selectedDay = calendarProjection.days.first?.date
                ?? monthInterval.start
            selectsFirstChargeAfterMonthChange = false
        }
    }

    private func moveMonth(by offset: Int) {
        guard let month = calendar.date(
            byAdding: .month,
            value: offset,
            to: displayedMonth
        ) else {
            return
        }
        selectMonth(month)
    }

    private func selectMonth(_ month: Date) {
        let normalizedMonth = calendar.dateInterval(of: .month, for: month)?.start
            ?? calendar.startOfDay(for: month)
        guard !calendar.isDate(
            normalizedMonth,
            equalTo: displayedMonth,
            toGranularity: .month
        ) else {
            return
        }
        displayedMonth = normalizedMonth
        selectedDay = normalizedMonth
        selectsFirstChargeAfterMonthChange = true
    }

    private func dayIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "upcoming.day.\(components.year ?? 0)-\(components.month ?? 0)-"
            + "\(components.day ?? 0)"
    }

    private func confirmationContext(
        for item: UpcomingTimelineItem
    ) -> UpcomingConfirmationPresentation? {
        guard item.kind == .expected,
              let subscription = subscriptionsByID[item.subscriptionID]
        else {
            return nil
        }
        let timeZone = billingTimeZone(
            identifier: subscription.billingSchedule.timeZoneIdentifier
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: item.date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return nil
        }
        let expectedOccurrence = ExpectedCharge(
            id: ScheduledChargeID(
                subscriptionID: subscription.id,
                year: year,
                month: month,
                day: day
            ),
            subscriptionID: subscription.id,
            scheduledDate: item.date,
            amount: item.amount
        )
        let confirmedIDs = confirmedSourceChargeIDsBySubscription[
            subscription.id
        ] ?? []
        guard ConfirmChargeEligibility.isEligible(
            expectedOccurrence: expectedOccurrence,
            confirmedIDs: confirmedIDs,
            now: Date(),
            billingTimeZone: timeZone
        ) else {
            return nil
        }
        return UpcomingConfirmationPresentation(
            subscription: subscription,
            expectedOccurrence: expectedOccurrence
        )
    }
}

#if os(iOS)
private struct UpcomingMonthCalendar: UIViewRepresentable {
    @Binding var selectedDay: Date
    let displayedMonth: Date
    let dayCounts: [Date: Int]
    let calendar: Calendar
    let onDisplayedMonthChange: (Date) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedDay: $selectedDay,
            calendar: calendar,
            onDisplayedMonthChange: onDisplayedMonthChange
        )
    }

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        configureLayoutMargins(of: calendarView)
        calendarView.calendar = calendar
        calendarView.locale = calendar.locale ?? .current
        calendarView.delegate = context.coordinator
        calendarView.selectionBehavior = UICalendarSelectionSingleDate(
            delegate: context.coordinator
        )
        calendarView.visibleDateComponents = monthComponents(for: displayedMonth)
        calendarView.accessibilityIdentifier = "upcoming.calendar"
        return calendarView
    }

    func updateUIView(_ calendarView: UICalendarView, context: Context) {
        configureLayoutMargins(of: calendarView)
        context.coordinator.calendar = calendar
        context.coordinator.onDisplayedMonthChange = onDisplayedMonthChange
        context.coordinator.dayCounts = dayCounts

        let monthComponents = monthComponents(for: displayedMonth)
        if calendarView.visibleDateComponents.year != monthComponents.year
            || calendarView.visibleDateComponents.month != monthComponents.month {
            // Respect Reduce Motion: jump straight to the paged month.
            calendarView.setVisibleDateComponents(
                monthComponents,
                animated: !UIAccessibility.isReduceMotionEnabled
            )
        }

        if let selection = calendarView.selectionBehavior
            as? UICalendarSelectionSingleDate {
            let selectedComponents = calendar.dateComponents(
                [.year, .month, .day],
                from: selectedDay
            )
            if selection.selectedDate != selectedComponents {
                selection.setSelected(selectedComponents, animated: false)
            }
        }

        calendarView.reloadDecorations(
            forDateComponents: dateComponentsInDisplayedMonth(),
            animated: false
        )
    }

    private func configureLayoutMargins(of calendarView: UICalendarView) {
        // Keep the UIKit calendar's day cells inset from its SwiftUI/List row
        // on every update; otherwise the system can lay digits against the
        // wrapper edge when the month or selection changes.
        calendarView.preservesSuperviewLayoutMargins = false
        calendarView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 8,
            bottom: 8,
            trailing: 8
        )
    }

    private func monthComponents(for date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month], from: date)
    }

    private func dateComponentsInDisplayedMonth() -> [DateComponents] {
        guard let interval = calendar.dateInterval(
            of: .month,
            for: displayedMonth
        ) else {
            return []
        }
        var components: [DateComponents] = []
        var date = interval.start
        while date < interval.end {
            components.append(
                calendar.dateComponents([.year, .month, .day], from: date)
            )
            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) else {
                break
            }
            date = nextDate
        }
        return components
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate,
        UICalendarSelectionSingleDateDelegate {
        @Binding private var selectedDay: Date
        var calendar: Calendar
        var dayCounts: [Date: Int] = [:]
        var onDisplayedMonthChange: (Date) -> Void

        init(
            selectedDay: Binding<Date>,
            calendar: Calendar,
            onDisplayedMonthChange: @escaping (Date) -> Void
        ) {
            _selectedDay = selectedDay
            self.calendar = calendar
            self.onDisplayedMonthChange = onDisplayedMonthChange
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            didSelectDate dateComponents: DateComponents?
        ) {
            guard let dateComponents,
                  let date = calendar.date(from: dateComponents)
            else {
                return
            }
            selectedDay = calendar.startOfDay(for: date)
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            canSelectDate dateComponents: DateComponents?
        ) -> Bool {
            true
        }

        func calendarView(
            _ calendarView: UICalendarView,
            didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents
        ) {
            guard let visibleMonth = calendar.date(
                from: calendarView.visibleDateComponents
            ) else {
                return
            }
            onDisplayedMonthChange(visibleMonth)
        }

        func calendarView(
            _ calendarView: UICalendarView,
            decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            guard let date = calendar.date(from: dateComponents) else {
                return nil
            }
            let count = dayCounts[calendar.startOfDay(for: date)] ?? 0
            guard count > 0 else { return nil }

            return .customView {
                let badge = UILabel()
                badge.text = count > 99 ? "99+" : "\(count)"
                badge.textAlignment = .center
                badge.font = .preferredFont(forTextStyle: .caption2)
                badge.adjustsFontForContentSizeCategory = true
                badge.textColor = .white
                badge.backgroundColor = .tintColor
                badge.layer.cornerCurve = .continuous
                badge.layer.cornerRadius = 9
                badge.clipsToBounds = true
                badge.translatesAutoresizingMaskIntoConstraints = false
                badge.widthAnchor.constraint(
                    greaterThanOrEqualTo: badge.heightAnchor
                ).isActive = true
                badge.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: 18
                ).isActive = true
                badge.setContentHuggingPriority(.required, for: .horizontal)
                badge.setContentHuggingPriority(.required, for: .vertical)
                badge.setContentCompressionResistancePriority(
                    .required, for: .horizontal
                )
                badge.setContentCompressionResistancePriority(
                    .required, for: .vertical
                )
                badge.isAccessibilityElement = true
                badge.accessibilityLabel = String(
                    localized: "\(count) charges"
                )
                return badge
            }
        }
    }
}
#endif

private struct UpcomingConfirmationPresentation: Identifiable {
    let subscription: Subscription
    let expectedOccurrence: ExpectedCharge

    var id: String {
        let occurrenceID = expectedOccurrence.id
        return "\(occurrenceID.subscriptionID.uuidString)-"
            + "\(occurrenceID.year)-\(occurrenceID.month)-"
            + "\(occurrenceID.day)"
    }
}

private struct UpcomingTimelineRow: View {
    let item: UpcomingTimelineItem
    let billingTimeZoneIdentifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(
                systemName: item.kind == .expected
                    ? "calendar"
                    : "checkmark.circle"
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.serviceName)
                    .lineLimit(2)
                Text(statusTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedMoney(item.amount))
                    .lineLimit(2)
                Text(
                    formattedBillingDate(
                        item.date,
                        timeZoneIdentifier: billingTimeZoneIdentifier,
                        locale: .current
                    )
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.serviceName), \(statusAccessibilityText), "
                + "\(formattedMoney(item.amount)), "
                + formattedBillingDate(
                    item.date,
                    timeZoneIdentifier: billingTimeZoneIdentifier,
                    locale: .current
                )
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

struct FirstRunSetupView: View {
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
    @State private var expectedSetupRevision: UInt64

    init(
        workspace: SubscriptionWorkspace,
        onFinished: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.onFinished = onFinished
        _expectedSetupRevision = State(
            initialValue: workspace.setupRevision
        )
    }

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
                        canSave: { setupInteractionIsActive },
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
        .onChange(of: workspace.setupRevision) { _, revision in
            guard revision != expectedSetupRevision else { return }
            finish()
        }
    }

    private var preferencesContent: some View {
        Form {
            Section {
                Text("Choose the defaults you want to use throughout the app.")
                    .foregroundStyle(.secondary)
            }

            Picker("Primary Currency", selection: $primaryCurrency) {
                ForEach(Currency.allCases, id: \.rawValue) { currency in
                    Text(currency.rawValue).tag(currency)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Primary Currency")
            .accessibilityIdentifier("setup.primary-currency")
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Calendar Projection") {
                Picker("Calendar Projection", selection: $horizon) {
                    Text("6 Months").tag(CalendarProjectionHorizon.sixMonths)
                    Text("12 Months").tag(CalendarProjectionHorizon.twelveMonths)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Calendar Projection")
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
                    guard setupInteractionIsActive else {
                        finish()
                        return
                    }
                    workspace.skipSetup()
                    guard !setupPersistenceFailed else { return }
                    expectedSetupRevision = workspace.setupRevision
                    finish()
                }
                .accessibilityIdentifier("setup.skip")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") {
                    guard setupInteractionIsActive else {
                        finish()
                        return
                    }
                    workspace.updatePreferences(
                        primaryCurrency: primaryCurrency,
                        calendarProjectionHorizon: horizon
                    )
                    if case .failed = workspace.setupState {
                        return
                    }
                    expectedSetupRevision = workspace.setupRevision
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
                            ? LocalizedStringKey("Selected")
                            : LocalizedStringKey("Not selected")
                    )
                    .accessibilityAddTraits(
                        selectedPresetIDs.contains(preset.id) ? .isSelected : []
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
                        showsCancellationAction: false,
                        canSave: { setupInteractionIsActive }
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
                        guard setupInteractionIsActive else {
                            finish()
                            return
                        }
                        workspace.completeSetup()
                        guard !setupPersistenceFailed else { return }
                        expectedSetupRevision = workspace.setupRevision
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
             .failed(let preferences),
             .configurationSaveFailed(let preferences):
            primaryCurrency = preferences.primaryCurrency
            horizon = preferences.calendarProjectionHorizon
        case .notLoaded, .loadFailed:
            break
        }
    }

    private var setupInteractionIsActive: Bool {
        SetupSheetPresentation.isSetupInteractionActive(
            for: workspace.setupState,
            expectedSetupRevision: expectedSetupRevision,
            currentSetupRevision: workspace.setupRevision
        )
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

struct UserPreferencesView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let onResumeSetup: () -> Void

    @State private var primaryCurrency: Currency = .cny
    @State private var horizon: CalendarProjectionHorizon = .twelveMonths
    @State private var hideAmountsInCalendar = false
    @State private var menuBarModeEnabled = false
    @State private var appearanceMode: AppearanceMode = .system
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    preferenceButton(
                        title: "System",
                        isSelected: appearanceMode == .system,
                        identifier: "preferences.appearance.system"
                    ) {
                        appearanceMode = .system
                    }
                    preferenceButton(
                        title: "Light",
                        isSelected: appearanceMode == .light,
                        identifier: "preferences.appearance.light"
                    ) {
                        appearanceMode = .light
                    }
                    preferenceButton(
                        title: "Dark",
                        isSelected: appearanceMode == .dark,
                        identifier: "preferences.appearance.dark"
                    ) {
                        appearanceMode = .dark
                    }
                }

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
                            menuBarModeEnabled: menuBarModeEnabled,
                            appearanceMode: appearanceMode
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
        .accessibilityValue(
            isSelected
                ? LocalizedStringKey("Selected")
                : LocalizedStringKey("Not selected")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var isSetupSaveFailure: Bool {
        workspace.setupState.hasPreferenceSaveFailure
    }

    private func applyWorkspacePreferences() {
        switch workspace.setupState {
        case .needsSetup(let preferences),
             .completed(let preferences),
             .skipped(let preferences),
             .failed(let preferences),
             .configurationSaveFailed(let preferences):
            primaryCurrency = preferences.primaryCurrency
            horizon = preferences.calendarProjectionHorizon
            hideAmountsInCalendar = preferences.hideAmountsInCalendar
            menuBarModeEnabled = preferences.menuBarModeEnabled
            appearanceMode = preferences.appearanceMode
        case .notLoaded, .loadFailed:
            break
        }
    }
}

struct SetupLoadFailureView: View {
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Load Setup Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your library was not changed. Try loading it again.")
        } actions: {
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("setup.retry-load")
        }
    }
}

private struct SyncStatusView: View {
    let workspace: SubscriptionWorkspace

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .accessibilityElement(children: .combine)
            Spacer()
            if workspace.syncStatus == .requiresAttention {
                Button("Try Again") {
                    Task { await workspace.refreshSyncStatus() }
                }
            }
        }
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
