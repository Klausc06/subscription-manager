import SubscriptionCore
import SwiftUI

struct UserPreferencesView: View {
    @Environment(\.dismiss) private var dismiss

    let workspace: SubscriptionWorkspace
    let onResumeSetup: () -> Void

    @State private var primaryCurrency: Currency = .cny
    @State private var horizon: CalendarProjectionHorizon = .twelveMonths
    @State private var hideAmountsInCalendar = false
    @State private var menuBarModeEnabled = false
    @State private var appearanceMode: AppearanceMode = .system
    @State private var notificationsEnabled = false
    @State private var notificationAdvanceDays = 1
    @State private var saveFailed = false
    private let notificationScheduler = RenewalNotificationScheduler()

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

                Section("Notifications") {
                    Toggle(
                        "Renewal Reminders",
                        isOn: $notificationsEnabled
                    )
                    .accessibilityIdentifier("preferences.notifications.enabled")
                    if notificationsEnabled {
                        Stepper(
                            "\(notificationAdvanceDays) day(s) before",
                            value: $notificationAdvanceDays,
                            in: 1...30
                        )
                        .accessibilityIdentifier(
                            "preferences.notifications.advance-days"
                        )
                    }
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
                        saveNotificationPreferences()
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
        notificationsEnabled = notificationScheduler.isEnabled
        notificationAdvanceDays = notificationScheduler.advanceDays
    }

    private func saveNotificationPreferences() {
        let wasEnabled = notificationScheduler.isEnabled
        notificationScheduler.isEnabled = notificationsEnabled
        notificationScheduler.advanceDays = notificationAdvanceDays
        if notificationsEnabled, !wasEnabled {
            Task {
                let granted = await notificationScheduler.requestAuthorization()
                if !granted {
                    notificationScheduler.isEnabled = false
                }
            }
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

struct SyncStatusView: View {
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
