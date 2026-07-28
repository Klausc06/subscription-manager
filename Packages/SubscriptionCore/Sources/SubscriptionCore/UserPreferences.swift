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
    public let hideAmountsInCalendar: Bool
    public let setupStatus: SetupStatus

    public init(
        primaryCurrency: Currency,
        calendarProjectionHorizon: CalendarProjectionHorizon,
        hideAmountsInCalendar: Bool = false,
        setupStatus: SetupStatus
    ) {
        self.primaryCurrency = primaryCurrency
        self.calendarProjectionHorizon = calendarProjectionHorizon
        self.hideAmountsInCalendar = hideAmountsInCalendar
        self.setupStatus = setupStatus
    }

    public static let `default` = UserPreferences(
        primaryCurrency: .cny,
        calendarProjectionHorizon: .twelveMonths,
        hideAmountsInCalendar: false,
        setupStatus: .notCompleted
    )

    private enum CodingKeys: String, CodingKey {
        case primaryCurrency
        case calendarProjectionHorizon
        case hideAmountsInCalendar
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
