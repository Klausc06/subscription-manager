public enum CalendarProjectionHorizon: Int, CaseIterable, Codable, Sendable {
    case sixMonths = 6
    case twelveMonths = 12
}

public enum SetupStatus: String, Codable, Equatable, Sendable {
    case notCompleted
    case completed
    case skipped
}

public struct UserPreferences: Codable, Equatable, Sendable {
    public let primaryCurrency: Currency
    public let calendarProjectionHorizon: CalendarProjectionHorizon
    public let setupStatus: SetupStatus

    public init(
        primaryCurrency: Currency,
        calendarProjectionHorizon: CalendarProjectionHorizon,
        setupStatus: SetupStatus
    ) {
        self.primaryCurrency = primaryCurrency
        self.calendarProjectionHorizon = calendarProjectionHorizon
        self.setupStatus = setupStatus
    }

    public static let `default` = UserPreferences(
        primaryCurrency: .cny,
        calendarProjectionHorizon: .twelveMonths,
        setupStatus: .notCompleted
    )
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
