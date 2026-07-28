import SubscriptionCore
import SwiftUI

struct LibraryView: View {
    let workspace: SubscriptionWorkspace
    @State private var presentedSheet: LibrarySheet?
    @State private var isSetupPresented = false
    @State private var isPreferencesPresented = false

    var body: some View {
        NavigationStack {
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addSubscription:
                NavigationStack {
                    AddSubscriptionView(workspace: workspace)
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
            workspace.loadLibrary(scope: .current)
            let libraryIsEmpty: Bool
            if case .empty(.current) = workspace.libraryState {
                libraryIsEmpty = true
            } else {
                libraryIsEmpty = false
            }
            workspace.loadSetup(libraryIsEmpty: libraryIsEmpty)
            let arguments = ProcessInfo.processInfo.arguments
            let allowsUITestOnboarding = arguments.contains(
                "--ui-testing-onboarding"
            )
            let isUITesting = arguments.contains("--ui-testing")
            if case .needsSetup = workspace.setupState,
               !isUITesting || allowsUITestOnboarding
            {
                isSetupPresented = true
            }
        }
    }

    private func presentAddSubscription() {
        presentedSheet = .addSubscription
    }

    private func presentPreferences() {
        isPreferencesPresented = true
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
                    CatalogPresetDetailView(
                        workspace: workspace,
                        preset: preset,
                        onSubscriptionCreated: {
                            confirmedPresetIDs.insert(presetID)
                            navigationPath.removeAll()
                        }
                    )
                }
            }
        }
        .task {
            applyWorkspacePreferences()
            confirmedPresetIDs.formUnion(existingCatalogPresetIDs)
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
                    AddSubscriptionView(workspace: workspace)
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
        return Set(
            subscriptions.compactMap { subscription in
                let identity = subscription.serviceIdentity.rawValue
                guard identity.hasPrefix(prefix) else { return nil }
                return String(identity.dropFirst(prefix.count))
            }
        )
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

    var body: some View {
        libraryContent
            .navigationTitle(navigationTitle)
            .toolbar {
                if scope == .current {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") {
                            onPreferences()
                        }
                        .accessibilityIdentifier("library.settings")
                    }
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

private struct UserPreferencesView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let onResumeSetup: () -> Void

    @State private var primaryCurrency: Currency = .cny
    @State private var horizon: CalendarProjectionHorizon = .twelveMonths
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
                            calendarProjectionHorizon: horizon
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
        case .notLoaded:
            break
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
