import Foundation
import Observation

extension SubscriptionWorkspace {
    public func loadSetup(libraryIsEmpty: Bool) {
        loadSetup(
            libraryIsEmptyWhenPreferencesAreMissing: libraryIsEmpty
        )
    }
    func loadSetup(
        libraryIsEmptyWhenPreferencesAreMissing: Bool?
    ) {
        let fallback = UserPreferences.default
        for attempt in 0..<2 {
            do {
                let storedPreferences = try preferencesRepository?.loadPreferences()
                guard let preferences = storedPreferences else {
                    setupPreferencesLoadResult = .missing
                    guard let libraryIsEmptyWhenPreferencesAreMissing else {
                        setupState = .loadFailed
                        return
                    }
                    setupState = libraryIsEmptyWhenPreferencesAreMissing
                        ? .needsSetup(fallback)
                        : .completed(fallback)
                    return
                }
                setupPreferencesLoadResult = .stored
                switch preferences.setupStatus {
                case .notCompleted:
                    setupState = .needsSetup(preferences)
                case .completed:
                    setupState = .completed(preferences)
                case .skipped:
                    setupState = .skipped(preferences)
                }
                return
            } catch {
                if attempt == 1 {
                    setupPreferencesLoadResult = .failed
                    setupState = .loadFailed
                }
            }
        }
    }
    func markSetupLoadFailed() {
        setupState = .loadFailed
    }
    public func updatePreferences(
        primaryCurrency: Currency,
        calendarProjectionHorizon: CalendarProjectionHorizon,
        hideAmountsInCalendar: Bool? = nil,
        menuBarModeEnabled: Bool? = nil,
        appearanceMode: AppearanceMode? = nil
    ) {
        let previousPreferences = currentPreferences
        let retainsExistingLibraryConfigurationFailure: Bool
        if case .configurationSaveFailed = setupState {
            retainsExistingLibraryConfigurationFailure = true
        } else {
            retainsExistingLibraryConfigurationFailure = false
        }
        persistPreferences(
            UserPreferences(
                primaryCurrency: primaryCurrency,
                calendarProjectionHorizon: calendarProjectionHorizon,
                hideAmountsInCalendar: hideAmountsInCalendar
                    ?? currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: menuBarModeEnabled
                    ?? currentPreferences.menuBarModeEnabled,
                appearanceMode: appearanceMode
                    ?? currentPreferences.appearanceMode,
                setupStatus: currentPreferences.setupStatus
            ),
            stateOnFailure: { _ in
                retainsExistingLibraryConfigurationFailure
                    ? .configurationSaveFailed(previousPreferences)
                    : .failed(previousPreferences)
            }
        )
        reloadInsightsIfNeeded()
    }
    public func completeSetup() {
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: currentPreferences.menuBarModeEnabled,
                appearanceMode: currentPreferences.appearanceMode,
                setupStatus: .completed
            )
        )
    }
    func completeExistingLibrarySetup() {
        guard case .missing = setupPreferencesLoadResult else { return }
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: currentPreferences.menuBarModeEnabled,
                appearanceMode: currentPreferences.appearanceMode,
                setupStatus: .completed
            ),
            stateOnFailure: { .configurationSaveFailed($0) }
        )
    }
    public func skipSetup() {
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: currentPreferences.menuBarModeEnabled,
                appearanceMode: currentPreferences.appearanceMode,
                setupStatus: .skipped
            )
        )
    }
    public func resumeSetup() {
        persistPreferences(
            UserPreferences(
                primaryCurrency: currentPreferences.primaryCurrency,
                calendarProjectionHorizon: currentPreferences.calendarProjectionHorizon,
                hideAmountsInCalendar: currentPreferences.hideAmountsInCalendar,
                menuBarModeEnabled: currentPreferences.menuBarModeEnabled,
                appearanceMode: currentPreferences.appearanceMode,
                setupStatus: .notCompleted
            ),
            stateOnSuccess: { .needsSetup($0) }
        )
    }
    func persistPreferences(
        _ preferences: UserPreferences,
        stateOnSuccess: ((UserPreferences) -> SetupState)? = nil,
        stateOnFailure: ((UserPreferences) -> SetupState)? = nil
    ) {
        if preferencesRepository != nil {
            switch setupState {
            case .notLoaded, .loadFailed:
                return
            case .needsSetup,
                 .completed,
                 .skipped,
                 .failed,
                 .configurationSaveFailed:
                break
            }
        }
        do {
            try preferencesRepository?.savePreferences(preferences)
            if preferencesRepository != nil {
                markLocalChangesForSync()
                setupPreferencesLoadResult = .stored
            }
            setupState = stateOnSuccess?(preferences)
                ?? setupState(for: preferences)
            setupRevision &+= 1
        } catch {
            setupState = stateOnFailure?(preferences)
                ?? .failed(currentPreferences)
        }
    }
    func setupState(for preferences: UserPreferences) -> SetupState {
        switch preferences.setupStatus {
        case .notCompleted:
            .needsSetup(preferences)
        case .completed:
            .completed(preferences)
        case .skipped:
            .skipped(preferences)
        }
    }
}
