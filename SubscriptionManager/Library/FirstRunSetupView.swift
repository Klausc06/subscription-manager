import SubscriptionCore
import SwiftUI

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
