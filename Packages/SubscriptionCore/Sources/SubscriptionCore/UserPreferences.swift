public enum CalendarProjectionHorizon: Int, CaseIterable, Codable, Sendable {
    case sixMonths = 6
    case twelveMonths = 12
}

public enum SetupStatus: String, Codable, Equatable, Sendable {
    case notCompleted
    case completed
    case skipped
}

public enum AppearanceMode: String, CaseIterable, Codable, Equatable, Sendable {
    case system
    case light
    case dark
}

public struct UserPreferences: Codable, Equatable, Sendable {
    public let primaryCurrency: Currency
    public let calendarProjectionHorizon: CalendarProjectionHorizon
    public let hideAmountsInCalendar: Bool
    public let menuBarModeEnabled: Bool
    public let appearanceMode: AppearanceMode
    public let setupStatus: SetupStatus

    public init(
        primaryCurrency: Currency,
        calendarProjectionHorizon: CalendarProjectionHorizon,
        hideAmountsInCalendar: Bool = false,
        menuBarModeEnabled: Bool = false,
        appearanceMode: AppearanceMode = .system,
        setupStatus: SetupStatus
    ) {
        self.primaryCurrency = primaryCurrency
        self.calendarProjectionHorizon = calendarProjectionHorizon
        self.hideAmountsInCalendar = hideAmountsInCalendar
        self.menuBarModeEnabled = menuBarModeEnabled
        self.appearanceMode = appearanceMode
        self.setupStatus = setupStatus
    }

    public static let `default` = UserPreferences(
        primaryCurrency: .cny,
        calendarProjectionHorizon: .twelveMonths,
        hideAmountsInCalendar: false,
        menuBarModeEnabled: false,
        appearanceMode: .system,
        setupStatus: .notCompleted
    )

    private enum CodingKeys: String, CodingKey {
        case primaryCurrency
        case calendarProjectionHorizon
        case hideAmountsInCalendar
        case menuBarModeEnabled
        case appearanceMode
        case setupStatus
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryCurrency = try container.decode(
            Currency.self,
            forKey: .primaryCurrency
        )
        calendarProjectionHorizon = try container.decode(
            CalendarProjectionHorizon.self,
            forKey: .calendarProjectionHorizon
        )
        hideAmountsInCalendar = try container.decodeIfPresent(
            Bool.self,
            forKey: .hideAmountsInCalendar
        ) ?? false
        menuBarModeEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .menuBarModeEnabled
        ) ?? false
        appearanceMode = try container.decodeIfPresent(
            AppearanceMode.self,
            forKey: .appearanceMode
        ) ?? .system
        setupStatus = try container.decode(SetupStatus.self, forKey: .setupStatus)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primaryCurrency, forKey: .primaryCurrency)
        try container.encode(
            calendarProjectionHorizon,
            forKey: .calendarProjectionHorizon
        )
        try container.encode(
            hideAmountsInCalendar,
            forKey: .hideAmountsInCalendar
        )
        try container.encode(menuBarModeEnabled, forKey: .menuBarModeEnabled)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(setupStatus, forKey: .setupStatus)
    }
}

@MainActor
public protocol UserPreferencesRepository {
    func loadPreferences() throws -> UserPreferences?
    func savePreferences(_ preferences: UserPreferences) throws
}

public enum SetupState: Equatable, Sendable {
    case notLoaded
    case needsSetup(UserPreferences)
    case completed(UserPreferences)
    case skipped(UserPreferences)
    case failed(UserPreferences)
}

public extension SubscriptionWorkspace {
    /// Returns the setup library conclusion only when both scopes are reliable.
    /// A nil result keeps setup state unchanged for a failed or incomplete load.
    static func libraryIsEmptyForSetup(
        current: SubscriptionLibraryState,
        archived: SubscriptionLibraryState
    ) -> Bool? {
        switch (current, archived) {
        case (.empty(.current), .empty(.archived)):
            return true
        case let (.loaded(.current, summaries), .empty(.archived)):
            return summaries.isEmpty ? nil : false
        case let (.empty(.current), .loaded(.archived, summaries)):
            return summaries.isEmpty ? nil : false
        case let (
            .loaded(.current, currentSummaries),
            .loaded(.archived, archivedSummaries)
        ):
            return currentSummaries.isEmpty && archivedSummaries.isEmpty
                ? nil
                : false
        default:
            return nil
        }
    }

    /// Initializes setup without treating an unreliable library load as a
    /// reliable empty or non-empty conclusion.
    func initializeSetup(
        currentLibraryState: SubscriptionLibraryState,
        archivedLibraryState: SubscriptionLibraryState
    ) {
        guard case .notLoaded = setupState else { return }
        guard let libraryIsEmpty = Self.libraryIsEmptyForSetup(
            current: currentLibraryState,
            archived: archivedLibraryState
        ) else {
            loadSetup(libraryIsEmpty: true)
            return
        }

        loadSetup(libraryIsEmpty: libraryIsEmpty)
        markExistingLibraryAsConfiguredIfNeeded(
            currentLibraryState: currentLibraryState,
            archivedLibraryState: archivedLibraryState
        )
    }

    /// Persists the completed state for a library that predates preferences.
    /// Existing incomplete, skipped, or failed setup states remain unchanged.
    func markExistingLibraryAsConfiguredIfNeeded(
        currentLibraryState: SubscriptionLibraryState,
        archivedLibraryState: SubscriptionLibraryState
    ) {
        guard Self.libraryIsEmptyForSetup(
            current: currentLibraryState,
            archived: archivedLibraryState
        ) == false else { return }
        guard case .completed = setupState else { return }
        completeSetup()
    }
}
